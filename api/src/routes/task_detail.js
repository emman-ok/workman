import { Router } from 'express';
import { Tasks, Projects, Milestones, Users, Comments } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { validate, z } from '../middleware/validate.js';
import { notFound } from '../errors.js';

const router = Router();

const IdParams = z.object({ id: z.coerce.number().int().positive() });
const CommentParams = IdParams.extend({ commentId: z.coerce.number().int().positive() });
const StatusInput = z.object({ status: z.enum(['todo', 'in_progress', 'done']) });
const CommentInput = z.object({ body: z.string().trim().min(1, 'Write a message first.').max(5000) });

const taskInclude = [
  { model: Projects, as: 'project', attributes: ['id', 'name'] },
  { model: Milestones, as: 'milestone', attributes: ['id', 'title'] },
  { model: Users, as: 'assignee', attributes: ['id', 'name', 'photo'] },
  { model: Users, as: 'createdByRef', attributes: ['id', 'name'] },
];

const commentInclude = [{ model: Users, as: 'user', attributes: ['id', 'name', 'photo'] }];

async function loadTask(id) {
  const task = await Tasks.findByPk(id, { include: taskInclude });
  if (!task) throw notFound('Task not found.');
  const latest = await Comments.findAll({
    where: { task_id: id },
    include: commentInclude,
    order: [['created_at', 'DESC'], ['id', 'DESC']],
    limit: 200,
  });
  const comments = latest.map((c) => c.toJSON()).reverse();
  return { ...task.toJSON(), comments };
}

router.get('/:id', validate({ params: IdParams }), asyncHandler(async (req, res) => {
  res.json(await loadTask(req.params.id));
}));

router.patch('/:id/status', validate({ params: IdParams, body: StatusInput }), asyncHandler(async (req, res) => {
  const { id } = req.params;
  const { status } = req.body;
  const task = await Tasks.findByPk(id);
  if (!task) throw notFound('Task not found.');
  await Tasks.update({
    status,
    completed_at: status === 'done' ? (task.completed_at || new Date()) : null,
    updated_at: new Date(),
  }, { where: { id } });
  res.json(await loadTask(id));
}));

router.post('/:id/comments', validate({ params: IdParams, body: CommentInput }), asyncHandler(async (req, res) => {
  const { id } = req.params;
  const task = await Tasks.findByPk(id);
  if (!task) throw notFound('Task not found.');
  const created = await Comments.create({ task_id: id, user_id: req.user.id, body: req.body.body });
  const comment = await Comments.findByPk(created.id, { include: commentInclude });
  res.status(201).json(comment);
}));

router.delete('/:id/comments/:commentId', validate({ params: CommentParams }), asyncHandler(async (req, res) => {
  const { id, commentId } = req.params;
  const task = await Tasks.findByPk(id);
  if (!task) throw notFound('Task not found.');
  const comment = await Comments.findOne({ where: { id: commentId, task_id: id } });
  if (!comment) throw notFound('Comment not found.');
  await comment.destroy();
  res.status(204).end();
}));

export default router;
