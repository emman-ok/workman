import { Router } from 'express';
import { Tasks, Projects, Milestones, Users, ProjectTeams, TeamMembers, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { HttpError, notFound, badRequest } from '../errors.js';
import { validate, optional, listQuery, z } from '../middleware/validate.js';

const router = Router();

const PRIORITIES = ['low', 'medium', 'high', 'urgent'];

const TaskInput = z.object({
  project_id: z.number().int().positive(),
  milestone_id: optional(z.number().int().positive()),
  title: z.string().trim().min(1).max(200),
  description: optional(z.string().trim()),
  priority: z.enum(PRIORITIES).optional(),
  deadline: optional(z.iso.date()),
  assignee_id: optional(z.number().int().positive()),
});

function parseId(value) {
  const n = Number.parseInt(value, 10);
  return Number.isInteger(n) && n > 0 ? n : null;
}

// Ids of the users who belong to a team working on the project.
async function memberIds(projectId) {
  const links = await ProjectTeams.findAll({ where: { project_id: projectId }, attributes: ['team_id'], raw: true });
  const teamIds = [...new Set(links.map((l) => l.team_id))];
  if (teamIds.length === 0) return [];
  const members = await TeamMembers.findAll({ where: { team_id: teamIds }, attributes: ['user_id'], raw: true });
  return [...new Set(members.map((m) => m.user_id))];
}

router.get('/options', asyncHandler(async (req, res) => {
  res.json({ priorities: PRIORITIES });
}));

router.get('/options/projects', validate({ query: listQuery(['name'], { sort: 'name', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = {};
    if (search) where.name = { [Op.iLike]: '%' + search + '%' };
    const onlyId = parseId(req.query.id);
    if (onlyId) where.id = onlyId;
    const { rows, count } = await Projects.findAndCountAll({
      where,
      attributes: ['id', 'name', 'status'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  }));

router.get('/options/milestones', validate({ query: listQuery(['title', 'due_date'], { sort: 'title', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const projectId = parseId(req.query.project_id);
    if (!projectId) return res.json({ items: [], total: 0 });
    const where = { project_id: projectId };
    if (search) where.title = { [Op.iLike]: '%' + search + '%' };
    const { rows, count } = await Milestones.findAndCountAll({
      where,
      attributes: ['id', 'title', 'due_date', 'status'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  }));

router.get('/options/assignees', validate({ query: listQuery(['name'], { sort: 'name', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const projectId = parseId(req.query.project_id);
    if (!projectId) return res.json({ items: [], total: 0 });
    const ids = await memberIds(projectId);
    if (ids.length === 0) return res.json({ items: [], total: 0 });
    const where = { id: ids, is_active: true };
    if (search) where.name = { [Op.iLike]: '%' + search + '%' };
    const { rows, count } = await Users.findAndCountAll({
      where,
      attributes: ['id', 'name', 'email'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  }));

router.post('/', validate({ body: TaskInput }), asyncHandler(async (req, res) => {
  const body = req.body;

  const project = await Projects.findByPk(body.project_id, { attributes: ['id'] });
  if (!project) throw notFound('Project not found.');

  if (body.milestone_id) {
    const milestone = await Milestones.findByPk(body.milestone_id, { attributes: ['id', 'project_id'] });
    if (!milestone) throw notFound('Milestone not found.');
    if (milestone.project_id !== body.project_id) {
      throw new HttpError(400, 'This milestone belongs to another project.', { milestone_id: 'This milestone belongs to another project.' });
    }
  }

  if (body.assignee_id) {
    const ids = await memberIds(body.project_id);
    if (!ids.includes(body.assignee_id)) {
      throw new HttpError(400, 'The assignee must be a member of a team working on this project.', { assignee_id: 'Pick a member of a team working on this project.' });
    }
  }

  const values = { ...body, created_by: req.user.id };
  if (!values.priority) delete values.priority;
  const created = await Tasks.create(values);

  const row = await Tasks.findByPk(created.id, {
    include: [
      { model: Projects, as: 'project', attributes: ['id', 'name'] },
      { model: Milestones, as: 'milestone', attributes: ['id', 'title'] },
      { model: Users, as: 'assignee', attributes: ['id', 'name'] },
    ],
  });
  res.status(201).json(row || created.toJSON());
}));

export default router;
