import { Router } from 'express';
import { Users, Op } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { badRequest, notFound } from '../errors.js';
import { validate, listQuery, z } from '../middleware/validate.js';
import { sendExport } from '../export.js';

const router = Router();

const ROLES = ['admin', 'project_manager', 'team_member'];
const SAFE = { exclude: ['password_hash'] };

const ListQuery = listQuery(['name', 'email', 'role', 'created_at'], { sort: 'name', order: 'asc' }).extend({
  role: z.enum(ROLES).optional().catch(undefined),
  is_active: z.enum(['true', 'false']).optional().catch(undefined),
});

const listOptions = (query) => {
  const where = {};
  if (query.search) {
    where[Op.or] = [
      { name: { [Op.iLike]: `%${query.search}%` } },
      { email: { [Op.iLike]: `%${query.search}%` } },
    ];
  }
  if (query.role) where.role = query.role;
  if (query.is_active) where.is_active = query.is_active === 'true';
  const order = [[query.sort, String(query.order).toUpperCase()], ['id', 'ASC']];
  return { where, order };
};

const IdParams = { id: z.coerce.number().int().positive() };

const readRow = (id) => Users.findByPk(id, { attributes: SAFE });

router.get('/', validate({ query: ListQuery }), asyncHandler(async (req, res) => {
  const { page, limit } = req.query;
  const { where, order } = listOptions(req.query);
  const { rows, count } = await Users.findAndCountAll({
    where,
    order,
    attributes: SAFE,
    limit,
    offset: (page - 1) * limit,
    distinct: true,
  });
  res.json({ items: rows, total: count });
}));

router.get('/export', validate({ query: ListQuery }), asyncHandler(async (req, res) => {
  const { where, order } = listOptions(req.query);
  await sendExport(req, res, { model: Users, where, order });
}));

router.post('/bulk-delete', validate({ body: { ids: z.array(z.number().int().positive()).min(1).max(100) } }), asyncHandler(async (req, res) => {
  if (req.body.ids.includes(req.user.id)) {
    throw badRequest('You cannot delete your own account.');
  }
  const deleted = await Users.destroy({ where: { id: req.body.ids } });
  res.json({ deleted });
}));

router.patch('/:id/active', validate({ params: IdParams, body: z.object({ is_active: z.boolean() }) }), asyncHandler(async (req, res) => {
  const user = await Users.findByPk(req.params.id, { attributes: ['id'] });
  if (!user) throw notFound('Account not found.');
  if (req.params.id === req.user.id && req.body.is_active === false) {
    throw badRequest('You cannot deactivate your own account.');
  }
  await Users.update({ is_active: req.body.is_active }, { where: { id: req.params.id } });
  res.json(await readRow(req.params.id));
}));

router.patch('/:id/role', validate({ params: IdParams, body: z.object({ role: z.enum(ROLES) }) }), asyncHandler(async (req, res) => {
  const user = await Users.findByPk(req.params.id, { attributes: ['id'] });
  if (!user) throw notFound('Account not found.');
  if (req.params.id === req.user.id) {
    throw badRequest('You cannot change your own role.');
  }
  await Users.update({ role: req.body.role }, { where: { id: req.params.id } });
  res.json(await readRow(req.params.id));
}));

export default router;
