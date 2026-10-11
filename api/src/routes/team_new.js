import { Router } from 'express';
import { Teams, Users } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { validate, optional, z } from '../middleware/validate.js';

const router = Router();

const TeamInput = z.object({
  name: z.string().trim().min(1, 'Name is required.').max(150),
  description: optional(z.string().trim().max(5000)),
});

router.post(
  '/',
  validate({ body: TeamInput }),
  asyncHandler(async (req, res) => {
    const created = await Teams.create({ ...req.body, created_by: req.user.id });
    const row = await Teams.findByPk(created.id, {
      include: [{ model: Users, as: 'createdByRef', attributes: ['id', 'name'] }],
    });
    res.status(201).json(row);
  })
);

export default router;
