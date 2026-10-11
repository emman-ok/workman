// The accounts people sign in with: which table and columns (api/.env), and
// the security steps every authentication flow shares. Owned by AppWand. The
// authentication screens' routes/auth.js builds its flow from these; so may
// any page that creates accounts or changes passwords. What people sign in
// with and which flows are on is AUTH_OPTIONS (./options.g.js, from AppWand).
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { modelForTable, Op } from '../models/index.js';
import { HttpError, notFound } from '../errors.js';
import { z } from '../middleware/validate.js';
import { permissionsOf, roleNameOf } from '../access.js';
import { AUTH_OPTIONS } from './options.g.js';
import { checkCode, issueCode } from './codes.js';
import { sendCode } from './messages.js';

export { AUTH_OPTIONS };

export const COLUMNS = Object.freeze({
  table: process.env.AUTH_TABLE || 'users',
  id: process.env.AUTH_ID_COLUMN || 'id',
  email: process.env.AUTH_EMAIL_COLUMN || 'email',
  password: process.env.AUTH_PASSWORD_COLUMN || 'password_hash',
  name: process.env.AUTH_NAME_COLUMN || 'name',
  // Each of these is empty when the table has no such column.
  role: process.env.AUTH_ROLE_COLUMN || '',
  username: process.env.AUTH_USERNAME_COLUMN || '',
  phone: process.env.AUTH_PHONE_COLUMN || '',
  photo: process.env.AUTH_PHOTO_COLUMN || '',
});

/** The accounts table's Sequelize model. */
export function accounts() {
  const model = modelForTable(COLUMNS.table);
  if (!model) throw new HttpError(500, `The accounts table "${COLUMNS.table}" is missing from the database.`);
  return model;
}

const roleOf = (row) => (COLUMNS.role && row[COLUMNS.role] != null ? String(row[COLUMNS.role]) : null);
const valueOf = (row, column) => (column && row[column] != null && row[column] !== '' ? row[column] : null);

/** A phone number as digits, with its leading + kept: "+1 (555) 010-2030" → "+15550102030". */
export function normalizePhone(value) {
  const text = String(value ?? '').trim();
  const digits = text.replace(/\D/g, '');
  return text.startsWith('+') ? `+${digits}` : digits;
}

const LABELS = { email: 'email', username: 'username', phone: 'phone number' };

/** The ways people sign in (AUTH_OPTIONS.loginWith) whose column the table has. */
export const LOGIN_WITH = Object.freeze(AUTH_OPTIONS.loginWith.filter((mode) => COLUMNS[mode]));

/** "email", "email or username", "email, username or phone number". */
export const LOGIN_LABEL = (() => {
  const names = (LOGIN_WITH.length > 0 ? LOGIN_WITH : ['email']).map((mode) => LABELS[mode]);
  return names.length === 1 ? names[0] : `${names.slice(0, -1).join(', ')} or ${names[names.length - 1]}`;
})();

/** Zod schemas for the account fields, with readable messages. */
export const fields = Object.freeze({
  /** What a person signs in with: their email, username or phone number. */
  login: z.string().trim().min(1, `Enter your ${LOGIN_LABEL}.`).max(255),
  email: z.string().trim().toLowerCase().pipe(z.email('Enter a valid email address.')),
  username: z.string().trim()
    .min(3, 'A username needs at least 3 characters.')
    .max(50)
    .regex(/^[A-Za-z0-9._-]+$/, 'Use only letters, digits, dots, dashes and underscores.'),
  phone: z.string().trim().max(32).refine((value) => {
    const digits = normalizePhone(value).replace('+', '');
    return digits.length >= 6 && digits.length <= 15;
  }, 'Enter a valid phone number.'),
  password: z.string().min(6, 'The password must be at least 6 characters.').max(200),
  code: z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code.'),
});

/** The raw row (with the password hash), or null. Answer with publicUser(row). */
export const findByEmail = (email) => accounts().findOne({ where: { [COLUMNS.email]: email }, raw: true });
export const findById = (id) => accounts().findOne({ where: { [COLUMNS.id]: id }, raw: true });

/**
 * The raw row whose email, username or phone number (only the ways the app
 * signs in with, LOGIN_WITH) is [login], or null.
 */
export async function findByLogin(login) {
  const text = String(login ?? '').trim();
  if (text === '') return null;
  const any = [];
  for (const mode of LOGIN_WITH) {
    const column = COLUMNS[mode];
    if (mode === 'email') any.push({ [column]: text.toLowerCase() });
    if (mode === 'username') any.push({ [column]: { [Op.in]: [...new Set([text, text.toLowerCase()])] } });
    if (mode === 'phone') {
      const phone = normalizePhone(text);
      if (phone.replace('+', '').length >= 6) any.push({ [column]: { [Op.in]: [...new Set([text, phone])] } });
    }
  }
  if (any.length === 0) return null;
  return accounts().findOne({ where: { [Op.or]: any }, raw: true });
}

/**
 * The row without the password hash, plus id, email, name, role, username,
 * phone and photo; with the Roles & permissions plugin, also the permissions
 * of its role ('<page id>.<action>') and the role's name as role_name.
 */
export function publicUser(row) {
  const user = { ...row };
  delete user[COLUMNS.password];
  const permissions = permissionsOf(roleOf(row));
  const roleName = roleNameOf(roleOf(row));
  return {
    ...user,
    id: row[COLUMNS.id],
    email: row[COLUMNS.email],
    name: row[COLUMNS.name],
    role: roleOf(row),
    username: valueOf(row, COLUMNS.username),
    phone: valueOf(row, COLUMNS.phone),
    photo: valueOf(row, COLUMNS.photo),
    ...(permissions ? { permissions } : {}),
    ...(roleName ? { role_name: roleName } : {}),
  };
}

function tokenFor(row) {
  const claims = { id: row[COLUMNS.id], email: row[COLUMNS.email], name: row[COLUMNS.name], role: roleOf(row) };
  return jwt.sign(claims, process.env.JWT_SECRET, { expiresIn: process.env.JWT_EXPIRES_IN || '7d' });
}

/** Signs the account in: the answer the app's AuthController.signedIn takes. */
export const session = (row) => ({ token: tokenFor(row), user: publicUser(row) });

export const hashPassword = (password) => bcrypt.hash(String(password), 10);

/** Whether [password] matches the account's hash (PHP's $2y$ hashes too). */
export async function checkPassword(row, password) {
  const hash = String(row?.[COLUMNS.password] || '').replace(/^\$2y\$/, '$2a$');
  return hash !== '' && bcrypt.compare(String(password), hash);
}

export async function setPassword(id, password) {
  await accounts().update({ [COLUMNS.password]: await hashPassword(password) }, { where: { [COLUMNS.id]: id } });
}

/**
 * Tidies the email, username and phone number in [data] (column → value) and
 * throws 409, with the message under the field, when another account than
 * [exceptId] already has one of them.
 */
async function claimLogins(data, exceptId) {
  for (const key of ['email', 'username', 'phone']) {
    const column = COLUMNS[key];
    if (!column || data[column] == null) continue;
    let value = String(data[column]).trim();
    if (key === 'email') value = value.toLowerCase();
    if (key === 'phone') value = normalizePhone(value);
    if (value === '') {
      data[column] = null;
      continue;
    }
    data[column] = value;
    const where = { [column]: value };
    if (exceptId != null) where[COLUMNS.id] = { [Op.ne]: exceptId };
    if (await accounts().findOne({ where, attributes: [COLUMNS.id], raw: true })) {
      const message = `An account with this ${LABELS[key]} already exists.`;
      throw new HttpError(409, message, { [key]: message });
    }
  }
}

/**
 * Creates an account and returns its raw row. [values] (column → value) never
 * set the id, the password or the role: the role comes only from
 * [options.role], a value the calling code chose, or else the column's
 * default. A taken email, username or phone number is refused with 409.
 */
export async function createAccount(values, password, options = {}) {
  const data = { ...values };
  delete data[COLUMNS.id];
  delete data[COLUMNS.password];
  if (COLUMNS.role) {
    delete data[COLUMNS.role];
    if (options.role != null) data[COLUMNS.role] = options.role;
  }
  await claimLogins(data);
  data[COLUMNS.password] = await hashPassword(password);
  const created = await accounts().create(data);
  return findById(created.get(COLUMNS.id));
}

// ── One-time codes ────────────────────────────────────────────────────────

/** Where an account's codes go: the phone it signed in with, else its email, else its phone. */
function destination(row, login) {
  const email = String(row[COLUMNS.email] ?? '');
  const phone = COLUMNS.phone ? String(row[COLUMNS.phone] ?? '') : '';
  const byPhone = phone !== '' && normalizePhone(login) !== '' && normalizePhone(login) === normalizePhone(phone);
  if (phone !== '' && (byPhone || !email.includes('@'))) return { channel: 'sms', to: phone };
  if (email.includes('@')) return { channel: 'email', to: email };
  return null;
}

const wrongCode = () => new HttpError(400, 'That code is wrong or has expired.', { code: 'That code is wrong or has expired.' });

/**
 * Sends a 6-digit code for [purpose] ('sign-in' or 'reset') to the account
 * [login] names. It never says whether one was sent, so nobody learns which
 * accounts exist: the route answers 202 either way.
 */
async function sendCodeFor(purpose, login) {
  const row = await findByLogin(login);
  const to = row ? destination(row, login) : null;
  if (!to) return;
  const code = issueCode(`${purpose}:${row[COLUMNS.id]}`);
  // Null when one was sent less than a minute ago. Not awaited: how long
  // sending takes must not tell an existing account from a missing one.
  if (code !== null) sendCode({ ...to, code, purpose });
}

/** The account [login] names, when [code] is its current code for [purpose]. */
async function accountForCode(purpose, login, code) {
  const row = await findByLogin(login);
  if (!row || !checkCode(`${purpose}:${row[COLUMNS.id]}`, code)) throw wrongCode();
  return row;
}

function requireOption(on, what) {
  if (!on) throw notFound(`${what} is not turned on for this app.`);
}

/** Signing in with a code (AUTH_OPTIONS.otpLogin), step 1: send the code. */
export async function sendSignInCode(login) {
  requireOption(AUTH_OPTIONS.otpLogin, 'Signing in with a code');
  await sendCodeFor('sign-in', login);
}

/** Step 2: the account, when [code] is right (else 400). Answer session(row). */
export async function signInWithCode(login, code) {
  requireOption(AUTH_OPTIONS.otpLogin, 'Signing in with a code');
  return accountForCode('sign-in', login, code);
}

/** Forgot password (AUTH_OPTIONS.forgotPassword), step 1: send a reset code. */
export async function sendResetCode(login) {
  requireOption(AUTH_OPTIONS.forgotPassword, 'Resetting a password');
  await sendCodeFor('reset', login);
}

/** Step 2: sets the new password when [code] is right (else 400) and returns the row. Answer session(row). */
export async function resetPassword(login, code, password) {
  requireOption(AUTH_OPTIONS.forgotPassword, 'Resetting a password');
  const row = await accountForCode('reset', login, code);
  await setPassword(row[COLUMNS.id], password);
  return findById(row[COLUMNS.id]);
}

// ── The signed-in account (server.js mounts these behind requireAuth) ─────

/** GET /api/auth/me. */
export async function currentUser(req, res) {
  const row = await findById(req.user.id);
  if (!row) throw notFound('This account no longer exists.');
  res.json(publicUser(row));
}

const ProfileInput = z.object({
  name: z.string().trim().min(1, 'Enter your name.').max(100).optional(),
  email: fields.email.optional(),
  username: z.union([z.literal(''), fields.username]).nullable().optional(),
  phone: z.union([z.literal(''), fields.phone]).nullable().optional(),
  photo: z.string().trim().max(255).nullable().optional(),
});

const PasswordInput = z.object({
  current_password: z.string().min(1, 'Enter your current password.'),
  password: z.string().min(6, 'The new password must be at least 6 characters.').max(200),
});

/** A 4xx with the message under one field, the way validation errors come. */
const fieldError = (res, status, field, message) => res.status(status).json({ message, errors: { [field]: message } });

/**
 * PATCH /api/auth/me { name?, email?, username?, phone?, photo? }. Answers
 * session(row): the token carries the name and email. A field whose column
 * the table lacks is ignored; null or '' clears the username, phone or photo.
 */
export async function updateProfile(req, res) {
  const input = ProfileInput.parse(req.body ?? {});
  const row = await findById(req.user.id);
  if (!row) throw notFound('This account no longer exists.');
  const id = row[COLUMNS.id];
  const changes = {};
  // When the name column is the email column, the email is the name.
  if (input.name !== undefined && COLUMNS.name !== COLUMNS.email) changes[COLUMNS.name] = input.name;
  if (input.email !== undefined) changes[COLUMNS.email] = input.email;
  for (const key of ['username', 'phone', 'photo']) {
    if (input[key] !== undefined && COLUMNS[key]) changes[COLUMNS[key]] = input[key] === '' ? null : input[key];
  }
  await claimLogins(changes, id);
  // The email is the account's way in: it is never cleared.
  if (changes[COLUMNS.email] === null) delete changes[COLUMNS.email];
  if (Object.keys(changes).length > 0) await accounts().update(changes, { where: { [COLUMNS.id]: id } });
  res.json(session(await findById(id)));
}

/** POST /api/auth/me/password { current_password, password } → 204, when AUTH_OPTIONS.changePassword. */
export async function changePassword(req, res) {
  requireOption(AUTH_OPTIONS.changePassword, 'Changing the password');
  const { current_password: current, password } = PasswordInput.parse(req.body ?? {});
  const row = await findById(req.user.id);
  if (!row) throw notFound('This account no longer exists.');
  if (!(await checkPassword(row, current))) {
    return fieldError(res, 400, 'current_password', 'That is not your current password.');
  }
  await setPassword(row[COLUMNS.id], password);
  res.status(204).end();
}
