import { Router } from 'express';
import { Projects, Users, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { HttpError } from '../errors.js';
import { validate, optional, listQuery, z } from '../middleware/validate.js';

const router = Router();

const ProjectInput = z
  .object({
    name: z.string().trim().min(1).max(200),
    description: optional(z.string().trim()),
    status: z.string().trim().min(1).max(20).optional(),
    priority: z.string().trim().min(1).max(20).optional(),
    start_date: optional(z.iso.date()),
    deadline: optional(z.iso.date()),
    manager_id: optional(z.number().int().positive()),
  })
  .refine((d) => !d.start_date || !d.deadline || d.deadline >= d.start_date, {
    message: 'The deadline cannot be before the start date.',
    path: ['deadline'],
  });

const managersQuery = validate({
  query: listQuery(['name'], { sort: 'name', order: 'asc' }),
});

const listManagers = asyncHandler(async (req, res) => {
  const { page, limit, search, sort, order } = req.query;
  const where = {
    is_active: true,
    role: { [Op.in]: ['admin', 'project_manager'] },
  };
  if (search) {
    where.name = { [Op.iLike]: `%${search}%` };
  }
  const { rows, count } = await Users.findAndCountAll({
    where,
    attributes: ['id', 'name', 'email'],
    order: [[sort, order.toUpperCase()]],
    limit,
    offset: (page - 1) * limit,
  });
  res.json({ items: rows, total: count });
});

router.get('/managers', managersQuery, listManagers);
router.get('/options/managers', managersQuery, listManagers);

router.post(
  '/',
  validate({ body: ProjectInput }),
  asyncHandler(async (req, res) => {
    const values = req.body;
    if (values.manager_id) {
      const manager = await Users.findByPk(values.manager_id, { attributes: ['id'] });
      if (!manager) {
        throw new HttpError(400, 'The selected manager does not exist.', {
          manager_id: 'The selected manager does not exist.',
        });
      }
    }
    const created = await Projects.create(values);
    const project = await Projects.findByPk(created.id, {
      include: [{ model: Users, as: 'manager', attributes: ['id', 'name', 'email'] }],
    });
    res.status(201).json(project);
  })
);

export default router;
