import { Router } from 'express';
import { Milestones, Projects } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { notFound } from '../errors.js';
import { validate, optional, z } from '../middleware/validate.js';

const router = Router();

const MilestoneInput = z.object({
  title: z.string().trim().min(1).max(200),
  description: optional(z.string().trim()),
  due_date: z.iso.date(),
  status: z.string().trim().min(1).max(20),
});

const IdParams = z.object({ id: z.coerce.number().int().positive() });

async function loadMilestone(id) {
  return Milestones.findByPk(id, {
    include: [{ model: Projects, as: 'project', attributes: ['id', 'name'] }],
  });
}

router.get('/:id', validate({ params: IdParams }), asyncHandler(async (req, res) => {
  const row = await loadMilestone(req.params.id);
  if (!row) throw notFound('Milestone not found.');
  res.json(row);
}));

router.put('/:id', validate({ params: IdParams, body: MilestoneInput.partial() }), asyncHandler(async (req, res) => {
  const row = await Milestones.findByPk(req.params.id);
  if (!row) throw notFound('Milestone not found.');
  const values = { ...req.body, updated_at: new Date() };
  if (values.status !== undefined) {
    if (values.status === 'reached') {
      if (!row.reached_at) values.reached_at = new Date();
    } else {
      values.reached_at = null;
    }
  }
  await row.update(values);
  const fresh = await loadMilestone(req.params.id);
  res.json(fresh);
}));

export default router;
