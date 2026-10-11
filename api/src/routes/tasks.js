import { Router } from 'express';
import { Tasks, Projects, Users, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound } from '../errors.js';
import { validate, listQuery, z } from '../middleware/validate.js';
import { sendExport } from '../export.js';

const router = Router();

const SORT_FIELDS = ['id', 'title', 'deadline', 'priority', 'status', 'created_at'];

const ListQuery = listQuery(SORT_FIELDS, { sort: 'created_at', order: 'desc' }).extend({
  status: z.string().trim().max(20).optional().catch(undefined),
  priority: z.string().trim().max(20).optional().catch(undefined),
  project_id: z.coerce.number().int().positive().optional().catch(undefined),
  assignee_id: z.coerce.number().int().positive().optional().catch(undefined),
  deadline: z.enum(['overdue', 'today', 'week']).optional().catch(undefined),
});

const OptionsQuery = listQuery(['name'], { sort: 'name', order: 'asc' });

const IdParams = z.object({ id: z.coerce.number().int().positive() });

const StatusInput = z.object({
  status: z.enum(['todo', 'in_progress', 'done']),
});

const dayString = (offset = 0) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return d.toISOString().slice(0, 10);
};

const taskIncludes = () => [
  { model: Projects, as: 'project', attributes: ['id', 'name'] },
  { model: Users, as: 'assignee', attributes: ['id', 'name', 'photo'] },
];

const listOptions = (query) => {
  const { search, sort, order, status, priority, project_id, assignee_id, deadline } = query;
  const conditions = [];
  if (search) conditions.push({ title: { [Op.iLike]: `%${search}%` } });
  if (status) conditions.push({ status });
  if (priority) conditions.push({ priority });
  if (project_id) conditions.push({ project_id });
  if (assignee_id) conditions.push({ assignee_id });
  if (deadline === 'overdue') {
    conditions.push({ deadline: { [Op.lt]: dayString(0) } });
    conditions.push({ status: { [Op.ne]: 'done' } });
  } else if (deadline === 'today') {
    conditions.push({ deadline: dayString(0) });
  } else if (deadline === 'week') {
    conditions.push({ deadline: { [Op.between]: [dayString(0), dayString(7)] } });
  }
  return {
    where: conditions.length ? { [Op.and]: conditions } : {},
    include: taskIncludes(),
    order: [[sort, order.toUpperCase()], ['id', 'DESC']],
  };
};

router.get('/export', validate({ query: ListQuery }), asyncHandler(async (req, res) => {
  const { where, include, order } = listOptions(req.query);
  await sendExport(req, res, { model: Tasks, where, include, order });
}));

router.get('/options/projects', validate({ query: OptionsQuery }), asyncHandler(async (req, res) => {
  const { page, limit, search, order } = req.query;
  const { rows, count } = await Projects.findAndCountAll({
    where: search ? { name: { [Op.iLike]: `%${search}%` } } : {},
    attributes: ['id', 'name'],
    order: [['name', order.toUpperCase()]],
    limit,
    offset: (page - 1) * limit,
  });
  res.json({ items: rows, total: count });
}));

router.get('/options/users', validate({ query: OptionsQuery }), asyncHandler(async (req, res) => {
  const { page, limit, search, order } = req.query;
  const { rows, count } = await Users.findAndCountAll({
    where: search ? { name: { [Op.iLike]: `%${search}%` } } : {},
    attributes: ['id', 'name'],
    order: [['name', order.toUpperCase()]],
    limit,
    offset: (page - 1) * limit,
  });
  res.json({ items: rows, total: count });
}));

router.get('/', validate({ query: ListQuery }), asyncHandler(async (req, res) => {
  const { page, limit } = req.query;
  const { rows, count } = await Tasks.findAndCountAll({
    ...listOptions(req.query),
    limit,
    offset: (page - 1) * limit,
    distinct: true,
  });
  res.json({ items: rows, total: count });
}));

router.patch('/:id/status', validate({ params: IdParams, body: StatusInput }), asyncHandler(async (req, res) => {
  const task = await Tasks.findByPk(req.params.id);
  if (!task) throw notFound('Task not found.');
  const { status } = req.body;
  await task.update({
    status,
    completed_at: status === 'done' ? new Date() : null,
  });
  const fresh = await Tasks.findByPk(req.params.id, { include: taskIncludes() });
  res.json(fresh);
}));

router.delete('/:id', validate({ params: IdParams }), asyncHandler(async (req, res) => {
  const task = await Tasks.findByPk(req.params.id);
  if (!task) throw notFound('Task not found.');
  await task.destroy();
  res.status(204).end();
}));

export default router;
