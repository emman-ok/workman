import { Router } from 'express';
import { Tasks, Projects, Milestones, Users, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { badRequest, notFound } from '../errors.js';
import { validate, optional, listQuery, z } from '../middleware/validate.js';

const router = Router();

const TaskInput = z.object({
  project_id: z.number().int().positive(),
  milestone_id: optional(z.number().int().positive()),
  title: z.string().trim().min(1).max(200),
  description: optional(z.string().trim()),
  priority: z.string().trim().min(1).max(20),
  status: z.string().trim().min(1).max(20),
  deadline: optional(z.iso.date()),
  assignee_id: optional(z.number().int().positive()),
});

const IdParams = z.object({ id: z.coerce.number().int().positive() });

const taskInclude = () => [
  { model: Projects, as: 'project', attributes: ['id', 'name'] },
  { model: Milestones, as: 'milestone', attributes: ['id', 'title', 'project_id'] },
  { model: Users, as: 'assignee', attributes: ['id', 'name', 'email'] },
];

const loadTask = (id) => Tasks.findByPk(id, { include: taskInclude() });

router.get(
  '/options/projects',
  validate({ query: listQuery(['name'], { sort: 'name', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = search ? { name: { [Op.iLike]: `%${search}%` } } : {};
    const { rows, count } = await Projects.findAndCountAll({
      where,
      attributes: ['id', 'name'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  })
);

router.get(
  '/options/milestones',
  validate({ query: listQuery(['title', 'due_date'], { sort: 'title', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = {};
    if (search) where.title = { [Op.iLike]: `%${search}%` };
    const projectId = Number(req.query.project_id);
    if (Number.isInteger(projectId) && projectId > 0) where.project_id = projectId;
    const { rows, count } = await Milestones.findAndCountAll({
      where,
      attributes: ['id', 'title', 'project_id'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  })
);

router.get(
  '/options/users',
  validate({ query: listQuery(['name'], { sort: 'name', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = { is_active: true };
    if (search) {
      where[Op.or] = [
        { name: { [Op.iLike]: `%${search}%` } },
        { email: { [Op.iLike]: `%${search}%` } },
      ];
    }
    const { rows, count } = await Users.findAndCountAll({
      where,
      attributes: ['id', 'name', 'email'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  })
);

router.get(
  '/:id',
  validate({ params: IdParams }),
  asyncHandler(async (req, res) => {
    const task = await loadTask(req.params.id);
    if (!task) throw notFound('Task not found.');
    res.json(task);
  })
);

router.put(
  '/:id',
  validate({ params: IdParams, body: TaskInput.partial() }),
  asyncHandler(async (req, res) => {
    const task = await Tasks.findByPk(req.params.id);
    if (!task) throw notFound('Task not found.');
    const values = { ...req.body };

    const projectId = values.project_id ?? task.project_id;
    if (values.project_id !== undefined) {
      const project = await Projects.findByPk(values.project_id, { attributes: ['id'] });
      if (!project) throw badRequest('The selected project does not exist.');
    }
    if (values.milestone_id) {
      const milestone = await Milestones.findByPk(values.milestone_id, { attributes: ['id', 'project_id'] });
      if (!milestone) throw badRequest('The selected milestone does not exist.');
      if (milestone.project_id !== projectId) {
        throw badRequest('The milestone does not belong to the selected project.');
      }
    }
    if (values.assignee_id) {
      const user = await Users.findByPk(values.assignee_id, { attributes: ['id'] });
      if (!user) throw badRequest('The selected assignee does not exist.');
    }

    if (values.status !== undefined) {
      if (values.status === 'done') {
        if (!task.completed_at) values.completed_at = new Date();
      } else {
        values.completed_at = null;
      }
    }

    await task.update(values);
    const fresh = await loadTask(task.id);
    res.json(fresh);
  })
);

export default router;
