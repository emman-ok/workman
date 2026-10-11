import { Router } from 'express';
import { Teams } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound } from '../errors.js';
import { validate, optional, z } from '../middleware/validate.js';

const router = Router();

const IdParams = z.object({ id: z.coerce.number().int().positive() });

const TeamInput = z.object({
  name: z.string().trim().min(1, 'Name is required.').max(150),
  description: optional(z.string().trim()),
});

router.get('/:id', validate({ params: IdParams }), asyncHandler(async (req, res) => {
  const team = await Teams.findByPk(req.params.id);
  if (!team) throw notFound('Team not found.');
  res.json(team);
}));

router.put('/:id', validate({ params: IdParams, body: TeamInput.partial() }), asyncHandler(async (req, res) => {
  const team = await Teams.findByPk(req.params.id);
  if (!team) throw notFound('Team not found.');
  await team.update(req.body);
  const fresh = await Teams.findByPk(req.params.id);
  res.json(fresh);
}));

export default router;
