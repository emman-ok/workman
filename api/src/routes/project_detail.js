import { Router } from 'express';
import { Projects, ProjectTeams, Teams, Milestones, Tasks, Users, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound } from '../errors.js';
import { validate, z } from '../middleware/validate.js';

const router = Router();

const IdParams = z.object({ id: z.coerce.number().int().positive() });
const StatusBody = z.object({ status: z.enum(['planned', 'active', 'on_hold', 'completed']) });

const TASK_DONE = ['done', 'completed'];
const MILESTONE_DONE = ['reached', 'completed', 'done'];

async function loadProject(id) {
  const project = await Projects.findByPk(id, {
    include: [{ model: Users, as: 'manager', attributes: ['id', 'name', 'email', 'photo'] }],
  });
  if (!project) throw notFound('Project not found.');

  const today = new Date().toISOString().slice(0, 10);
  const taskWhere = { project_id: id };
  const milestoneReached = {
    project_id: id,
    [Op.or]: [{ reached_at: { [Op.not]: null } }, { status: { [Op.in]: MILESTONE_DONE } }],
  };

  const [links, milestones, tasks, taskTotal, tasksDone, tasksOverdue, milestoneTotal, milestonesReached] = await Promise.all([
    ProjectTeams.findAll({
      where: { project_id: id },
      include: [{ model: Teams, as: 'team', attributes: ['id', 'name', 'description'] }],
      order: [['id', 'ASC']],
    }),
    Milestones.findAll({
      where: { project_id: id },
      attributes: ['id', 'title', 'description', 'due_date', 'status', 'reached_at'],
      order: [['due_date', 'ASC'], ['id', 'ASC']],
      limit: 10,
    }),
    Tasks.findAll({
      where: taskWhere,
      attributes: ['id', 'title', 'priority', 'status', 'deadline', 'assignee_id'],
      include: [{ model: Users, as: 'assignee', attributes: ['id', 'name'] }],
      order: [['deadline', 'ASC'], ['id', 'ASC']],
      limit: 10,
    }),
    Tasks.count({ where: taskWhere }),
    Tasks.count({ where: { project_id: id, status: { [Op.in]: TASK_DONE } } }),
    Tasks.count({
      where: {
        project_id: id,
        status: { [Op.notIn]: TASK_DONE },
        deadline: { [Op.lt]: today },
      },
    }),
    Milestones.count({ where: { project_id: id } }),
    Milestones.count({ where: milestoneReached }),
  ]);

  const teams = links
    .filter((link) => link.team)
    .map((link) => ({
      id: link.team.id,
      name: link.team.name,
      description: link.team.description,
    }));

  return {
    ...project.toJSON(),
    teams,
    milestones,
    tasks,
    stats: {
      task_total: taskTotal,
      tasks_done: tasksDone,
      tasks_overdue: tasksOverdue,
      milestone_total: milestoneTotal,
      milestones_reached: milestonesReached,
      team_total: teams.length,
      progress: taskTotal > 0 ? Math.round((tasksDone / taskTotal) * 100) : 0,
    },
  };
}

router.get('/:id', validate({ params: IdParams }), asyncHandler(async (req, res) => {
  res.json(await loadProject(req.params.id));
}));

router.patch('/:id/status', validate({ params: IdParams, body: StatusBody }), asyncHandler(async (req, res) => {
  const project = await Projects.findByPk(req.params.id);
  if (!project) throw notFound('Project not found.');
  await project.update({ status: req.body.status, updated_at: new Date() });
  res.json(await loadProject(req.params.id));
}));

export default router;
