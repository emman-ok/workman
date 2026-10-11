import { Router } from 'express';
import { Projects, Users, Tasks, Op, fn, col, literal } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound } from '../errors.js';
import { validate, listQuery, z } from '../middleware/validate.js';
import { sendExport } from '../export.js';

const router = Router();

const SORTS = ['name', 'deadline', 'created_at', 'status'];

const ListQuery = listQuery(SORTS, { sort: 'created_at', order: 'desc' }).extend({
  status: z.string().trim().max(20).optional().catch(undefined),
  priority: z.string().trim().max(20).optional().catch(undefined),
});

// One place that builds where, include and order, so the list and the export always match.
const listOptions = (query) => {
  const { search, status, priority, sort, order } = query;
  const where = {};
  if (search) where.name = { [Op.iLike]: `%${search}%` };
  if (status) where.status = status;
  if (priority) where.priority = priority;
  const direction = String(order).toLowerCase() === 'asc' ? 'ASC' : 'DESC';
  return {
    where,
    include: [{ model: Users, as: 'manager', attributes: ['id', 'name'] }],
    order: [[sort, `${direction} NULLS LAST`], ['id', 'ASC']],
  };
};

router.get(
  '/',
  validate({ query: ListQuery }),
  asyncHandler(async (req, res) => {
    const { page, limit } = req.query;
    const { rows, count } = await Projects.findAndCountAll({
      ...listOptions(req.query),
      limit,
      offset: (page - 1) * limit,
      distinct: true,
    });

    const ids = rows.map((r) => r.id);
    const progressByProject = new Map();
    if (ids.length > 0) {
      const stats = await Tasks.findAll({
        attributes: [
          'project_id',
          [fn('COUNT', col('id')), 'total'],
          [literal("SUM(CASE WHEN status = 'done' THEN 1 ELSE 0 END)"), 'done'],
        ],
        where: { project_id: { [Op.in]: ids } },
        group: ['project_id'],
        raw: true,
      });
      for (const s of stats) {
        progressByProject.set(Number(s.project_id), {
          total: Number(s.total) || 0,
          done: Number(s.done) || 0,
        });
      }
    }

    const items = rows.map((row) => {
      const plain = row.get({ plain: true });
      const stat = progressByProject.get(Number(plain.id)) || { total: 0, done: 0 };
      return {
        ...plain,
        task_count: stat.total,
        done_count: stat.done,
        progress: stat.total > 0 ? Math.round((stat.done * 100) / stat.total) : 0,
      };
    });

    res.json({ items, total: count });
  })
);

router.get(
  '/export',
  validate({ query: ListQuery }),
  asyncHandler(async (req, res) => {
    await sendExport(req, res, { model: Projects, ...listOptions(req.query) });
  })
);

router.delete(
  '/:id',
  validate({ params: { id: z.coerce.number().int().positive() } }),
  asyncHandler(async (req, res) => {
    const project = await Projects.findByPk(req.params.id);
    if (!project) throw notFound('Project not found.');
    await project.destroy();
    res.status(204).end();
  })
);

export default router;
