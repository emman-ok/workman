import { Router } from 'express';
import { asyncHandler } from '../middleware/async.js';
import { validate, z } from '../middleware/validate.js';
import { unauthorized } from '../errors.js';
import { fields, findByLogin, checkPassword, session, LOGIN_LABEL } from '../auth/accounts.js';

const router = Router();

const LoginInput = z.object({
  login: fields.login,
  password: z.string().min(1, 'Password is required.'),
});

router.post('/login', validate({ body: LoginInput }), asyncHandler(async (req, res) => {
  const { login, password } = req.body;
  const row = await findByLogin(login);
  const valid = row ? await checkPassword(row, password) : false;
  if (!row || !valid || row.is_active === false) {
    throw unauthorized(`Wrong ${LOGIN_LABEL} or password.`);
  }
  res.json(session(row));
}));

export default router;
