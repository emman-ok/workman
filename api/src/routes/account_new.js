import { Router } from 'express';
import { Users } from '../models/index.js';
import { asyncHandler } from '../middleware/async.js';
import { validate, z } from '../middleware/validate.js';
import { createAccount, findById, publicUser, fields } from '../auth/accounts.js';

const router = Router();

const AccountInput = z.object({
  name: z.string().trim().min(1, 'Name is required.').max(150),
  email: fields.email,
  password: fields.password,
  role: z.enum(['admin', 'project_manager', 'team_member']),
  is_active: z.boolean().optional(),
});

router.post(
  '/',
  validate({ body: AccountInput }),
  asyncHandler(async (req, res) => {
    const { name, email, password, role, is_active } = req.body;
    const active = is_active !== false;
    const created = await createAccount({ name, email, is_active: active }, password, { role });
    if (!active) {
      await Users.update({ is_active: false }, { where: { id: created.id } });
    }
    const row = await findById(created.id);
    res.status(201).json(publicUser(row));
  })
);

export default router;
