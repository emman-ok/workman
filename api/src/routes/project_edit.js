import { Router } from 'express';
import { Projects, Users, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound, badRequest } from '../errors.js';
import { validate, optional, listQuery, z } from '../middleware/validate.js';

const router = Router();

const ProjectInput = z.object({
  name: z.string().trim().min(1).max(200),
  description: optional(z.string().trim()),
  status: z.string().trim().min(1).max(20),
  priority: z.string().trim().min(1).max(20),
  start_date: optional(z.iso.date()),
  deadline: optional(z.iso.date()),
  manager_id: optional(z.number().int().positive()),
});

const IdParams = z.object({ id: z.coerce.number().int().positive() });

const withManager = [{ model: Users, as: 'manager', attributes: ['id', 'name'] }];

router.get(
  '/options/users',
  validate({ query: listQuery(['name'], { sort: 'name', order: 'asc' }) }),
  asyncHandler(async (req, res) => {
    const { page, limit, search, sort, order } = req.query;
    const where = { is_active: true };
    if (search) where.name = { [Op.iLike]: `%${search}%` };
    const { rows, count } = await Users.findAndCountAll({
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
  '/:id',
  validate({ params: IdParams }),
  asyncHandler(async (req, res) => {
    const project = await Projects.findByPk(req.params.id, { include: withManager });
    if (!project) throw notFound('Project not found.');
    res.json(project);
  })
);

router.put(
  '/:id',
  validate({ params: IdParams, body: ProjectInput.partial() }),
  asyncHandler(async (req, res) => {
    const project = await Projects.findByPk(req.params.id);
    if (!project) throw notFound('Project not found.');
    const start = 'start_date' in req.body ? req.body.start_date : project.start_date;
    const deadline = 'deadline' in req.body ? req.body.deadline : project.deadline;
    if (start && deadline && String(deadline) < String(start)) {
      throw badRequest('The deadline cannot be before the start date.');
    }
    await project.update({ ...req.body, updated_at: new Date() });
    const fresh = await Projects.findByPk(req.params.id, { include: withManager });
    res.json(fresh);
  })
);

export default router;
