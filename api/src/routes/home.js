import { Router } from 'express';
import { Projects, Tasks, Milestones, Op, fn, col } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { validate } from '../middleware/validate.js';
import { periodQuery, periodOf } from '../period.js';

const router = Router();

const today = () => new Date().toISOString().slice(0, 10);

router.get(
  '/',
  validate({ query: periodQuery }),
  asyncHandler(async (req, res) => {
    const period = periodOf(req.query);
    const day = today();

    const openTask = { status: { [Op.notIn]: ['done', 'cancelled'] } };
    const openProject = { status: { [Op.notIn]: ['completed', 'cancelled'] } };
    const completedNow = { completed_at: period.current(Tasks, 'completed_at') };
    const completedBefore = { completed_at: period.previous(Tasks, 'completed_at') };
    const bucket = period.bucket(Tasks, 'completed_at');

    const [
      activeProjects,
      openTasks,
      overdueTasks,
      completed,
      completedPrev,
      completedRows,
      projectsByStatus,
      tasksByPriority,
      projectDeadlines,
      taskDeadlines,
      upcomingMilestones,
    ] = await Promise.all([
      Projects.count({ where: { status: 'active' } }),
      Tasks.count({ where: openTask }),
      Tasks.count({ where: { ...openTask, deadline: { [Op.lt]: day } } }),
      Tasks.count({ where: completedNow }),
      Tasks.count({ where: completedBefore }),
      Tasks.findAll({
        attributes: [[bucket, 'bucket'], [fn('COUNT', col('id')), 'count']],
        where: completedNow,
        group: [bucket],
        order: [[bucket, 'ASC']],
        raw: true,
      }),
      Projects.findAll({
        attributes: ['status', [fn('COUNT', col('id')), 'count']],
        group: ['status'],
        order: [[fn('COUNT', col('id')), 'DESC']],
        raw: true,
      }),
      Tasks.findAll({
        attributes: ['priority', [fn('COUNT', col('id')), 'count']],
        group: ['priority'],
        order: [[fn('COUNT', col('id')), 'DESC']],
        raw: true,
      }),
      Projects.findAll({
        attributes: ['id', 'name', 'status', 'priority', 'deadline'],
        where: { ...openProject, deadline: { [Op.ne]: null } },
        order: [['deadline', 'ASC']],
        limit: 5,
      }),
      Tasks.findAll({
        attributes: ['id', 'title', 'status', 'priority', 'deadline', 'project_id'],
        where: { ...openTask, deadline: { [Op.ne]: null } },
        include: [{ model: Projects, as: 'project', attributes: ['id', 'name'] }],
        order: [['deadline', 'ASC']],
        limit: 5,
      }),
      Milestones.findAll({
        attributes: ['id', 'title', 'status', 'due_date', 'project_id'],
        where: { reached_at: null },
        include: [{ model: Projects, as: 'project', attributes: ['id', 'name'] }],
        order: [['due_date', 'ASC']],
        limit: 5,
      }),
    ]);

    res.json({
      activeProjects: { value: activeProjects },
      openTasks: { value: openTasks },
      overdueTasks: { value: overdueTasks },
      completedTasks: { value: completed, previous: completedPrev },
      completedByDay: period.fill(completedRows, 'bucket', { count: 0 }),
      projectsByStatus: projectsByStatus.map((r) => ({ status: r.status, count: Number(r.count) })),
      tasksByPriority: tasksByPriority.map((r) => ({ priority: r.priority, count: Number(r.count) })),
      projectDeadlines,
      taskDeadlines,
      upcomingMilestones,
    });
  })
);

export default router;
