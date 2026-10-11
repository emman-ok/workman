import { Router } from 'express';
import { Milestones, Projects, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound, badRequest } from '../errors.js';
import { validate, optional, listQuery, z } from '../middleware/validate.js';

const router = Router();

const MilestoneInput = z.object({
  project_id: z.number().int().positive(),
  title: z.string().trim().min(1).max(200),
  description: optional(z.string().trim()),
  due_date: z.iso.date(),
  status: z.enum(['pending', 'reached', 'late']).optional(),
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
  '/options/projects/:id',
  validate({ params: { id: z.coerce.number().int().positive() } }),
  asyncHandler(async (req, res) => {
    const project = await Projects.findByPk(req.params.id, { attributes: ['id', 'name'] });
    if (!project) throw notFound('Project not found.');
    res.json(project);
  })
);

router.post(
  '/',
  validate({ body: MilestoneInput }),
  asyncHandler(async (req, res) => {
    const project = await Projects.findByPk(req.body.project_id, { attributes: ['id'] });
    if (!project) throw badRequest('The selected project does not exist.');
    const values = { ...req.body };
    if (values.status === 'reached') values.reached_at = new Date();
    const created = await Milestones.create(values);
    const row = await Milestones.findByPk(created.id, {
      include: [{ model: Projects, as: 'project', attributes: ['id', 'name'] }],
    });
    res.status(201).json(row);
  })
);

export default router;
