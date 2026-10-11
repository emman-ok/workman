import { Router } from 'express';
import { where as sqlWhere } from 'sequelize';
import { Users, Op, fn, col } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { HttpError, notFound, badRequest } from '../errors.js';
import { validate, z } from '../middleware/validate.js';

const router = Router();

const ROLES = ['admin', 'project_manager', 'team_member'];

const IdParams = z.object({ id: z.coerce.number().int().positive() });

const AccountInput = z.object({
  name: z.string().trim().min(1).max(150),
  email: z.email().max(255),
  role: z.enum(ROLES),
  is_active: z.boolean(),
});

const SAFE_ATTRIBUTES = { exclude: ['password_hash'] };

router.get(
  '/:id',
  validate({ params: IdParams }),
  asyncHandler(async (req, res) => {
    const row = await Users.findByPk(req.params.id, { attributes: SAFE_ATTRIBUTES });
    if (!row) throw notFound('Account not found.');
    res.json(row);
  })
);

router.put(
  '/:id',
  validate({ params: IdParams, body: AccountInput.partial() }),
  asyncHandler(async (req, res) => {
    const id = req.params.id;
    const row = await Users.findByPk(id, { attributes: SAFE_ATTRIBUTES });
    if (!row) throw notFound('Account not found.');

    const values = req.body;

    if (req.user && req.user.id === id) {
      if (values.is_active === false) {
        throw badRequest('You cannot deactivate your own account.');
      }
      if (values.role !== undefined && values.role !== 'admin') {
        throw badRequest('You cannot remove your own admin role.');
      }
    }

    if (values.email !== undefined) {
      const taken = await Users.findOne({
        attributes: ['id'],
        where: {
          [Op.and]: [
            sqlWhere(fn('lower', col('email')), values.email.toLowerCase()),
            { id: { [Op.ne]: id } },
          ],
        },
      });
      if (taken) {
        throw new HttpError(409, 'This email is already in use.', {
          email: 'This email is already in use.',
        });
      }
    }

    await Users.update(values, { where: { id } });
    const updated = await Users.findByPk(id, { attributes: SAFE_ATTRIBUTES });
    res.json(updated);
  })
);

export default router;
