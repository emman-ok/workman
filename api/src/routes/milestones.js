import { Router } from 'express';
import { Milestones, Projects, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound } from '../errors.js';
import { validate, listQuery, z } from '../middleware/validate.js';

const router = Router();

const DONE_STATUSES = ['reached', 'completed', 'done'];

function todayString() {
  return new Date().toISOString().slice(0, 10);
}

function isDone(row) {
  return row.reached_at != null || DONE_STATUSES.includes(row.status);
}

function stateOf(row) {
  if (isDone(row)) return 'done';
  if (row.due_date && String(row.due_date).slice(0, 10) < todayString()) return 'late';
  return 'upcoming';
}

function present(row) {
  const json = row.toJSON();
  json.state = stateOf(json);
  return json;
}

const projectInclude = [{ model: Projects, as: 'project', attributes: ['id', 'name'] }];

const ListQuery = listQuery(['due_date', 'title', 'status', 'created_at'], { sort: 'due_date', order: 'asc' }).extend({
  project_id: z.coerce.number().int().positive().optional().catch(undefined),
  status: z.enum(['done', 'upcoming', 'late']).optional().catch(undefined),
});

router.get(
  '/options/projects',
  validate({ query: listQuery(['name'], { sort: 'name', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const { rows, count } = await Projects.findAndCountAll({
      where: search ? { name: { [Op.iLike]: `%${search}%` } } : {},
      attributes: ['id', 'name'],
      order: [[sort, order.toUpperCase()]],
      limit,
      offset: (page - 1) * limit,
    });
    res.json({ items: rows, total: count });
  })
);

router.get(
  '/',
  validate({ query: ListQuery }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order, project_id, status } = req.query;
    const conditions = [];
    if (search) {
      conditions.push({
        [Op.or]: [
          { title: { [Op.iLike]: `%${search}%` } },
          { '$project.name$': { [Op.iLike]: `%${search}%` } },
        ],
      });
    }
    if (project_id) conditions.push({ project_id });
    if (status === 'done') {
      conditions.push({
        [Op.or]: [{ reached_at: { [Op.ne]: null } }, { status: { [Op.in]: DONE_STATUSES } }],
      });
    } else if (status === 'late' || status === 'upcoming') {
      conditions.push({ reached_at: null, status: { [Op.notIn]: DONE_STATUSES } });
      conditions.push({
        due_date: status === 'late' ? { [Op.lt]: todayString() } : { [Op.gte]: todayString() },
      });
    }
    const where = conditions.length ? { [Op.and]: conditions } : {};
    const { rows, count } = await Milestones.findAndCountAll({
      where,
      include: projectInclude,
      order: [[sort, order.toUpperCase()], ['id', 'ASC']],
      limit,
      offset: (page - 1) * limit,
      distinct: true,
    });
    res.json({ items: rows.map(present), total: count });
  })
);

router.patch(
  '/:id/reach',
  validate({ params: { id: z.coerce.number().int().positive() } }),
  asyncHandler(async (req, res) => {
    const milestone = await Milestones.findByPk(req.params.id);
    if (!milestone) throw notFound('Milestone not found.');
    if (!isDone(milestone)) {
      await milestone.update({ status: 'reached', reached_at: new Date() });
    }
    const fresh = await Milestones.findByPk(req.params.id, { include: projectInclude });
    res.json(present(fresh));
  })
);

router.delete(
  '/:id',
  validate({ params: { id: z.coerce.number().int().positive() } }),
  asyncHandler(async (req, res) => {
    const milestone = await Milestones.findByPk(req.params.id);
    if (!milestone) throw notFound('Milestone not found.');
    await milestone.destroy();
    res.status(204).end();
  })
);

export default router;
