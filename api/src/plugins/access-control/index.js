// Roles & permissions: the roles and what each may do are rows in the
// database (access_roles, access_permissions), managed in the app on its
// "Roles & permissions" page. A permission is '<page id>.<action>'; the
// actions are view, create, edit, delete, export and import, plus 'all' on a
// page over tables whose records belong to a person (the Record ownership
// plugin, which asks can() for it): reaching everyone's records there.
//
// Nothing in a page's code: routes/index.js puts check() in front of every
// page behind sign-in, and the request's method and path say which action it
// is. GET is view (GET /export is export), POST / is create (POST /import is
// import, POST /bulk-delete is delete, any other POST is edit), PUT and PATCH
// are edit, DELETE is delete.
//
// The page plan (permissions.g.js) is only where it starts: the first time
// the API sees a role or a page's action, the plan's roles get it. After
// that the database decides.
//
// Owned by AppWand: ACCESS_ADMIN_ROLES, ACCESS_FIRST_ADMIN and
// ACCESS_DEFAULT_ROLE in .env are set in AppWand (Plugins).
import { Router } from 'express';
import { pageRouters, setAccess } from '../../access.js';
import { accounts, COLUMNS, findByEmail, findById } from '../../auth/accounts.js';
import { badRequest, forbidden, HttpError, notFound, unauthorized } from '../../errors.js';
import { asyncHandler } from '../../middleware/async.js';
import { requireAuth } from '../../middleware/auth.js';
import { listQuery, validate, z } from '../../middleware/validate.js';
import { modelForTable, Op, sequelize } from '../../models/index.js';
import catalog from '../../permissions.g.js';

const ROLES = 'access_roles';
const GRANTS = 'access_permissions';
const SEEDED = 'access_seeded';

const ACTIONS = ['view', 'create', 'edit', 'delete', 'export', 'import', 'all'];

/** Opening the Roles & permissions page and changing what is on it. */
const MANAGE = 'access.manage';

const list = (value) => String(value ?? '').split(',').map((item) => item.trim()).filter(Boolean);

/** Roles that always have every permission. */
const ADMIN_ROLES = new Set(list(process.env.ACCESS_ADMIN_ROLES));
if (ADMIN_ROLES.size === 0) ADMIN_ROLES.add('admin');

/** What an account without a role is treated as; '' for no permissions. */
let DEFAULT_ROLE = String(process.env.ACCESS_DEFAULT_ROLE || catalog.defaultRole || '').trim();
if (ADMIN_ROLES.has(DEFAULT_ROLE)) {
  console.warn('[access-control] ACCESS_DEFAULT_ROLE is an administrator role, so it is ignored.');
  DEFAULT_ROLE = '';
}

/** Made an administrator at start while nobody is one. */
const FIRST_ADMIN = String(process.env.ACCESS_FIRST_ADMIN || '').trim().toLowerCase();

/** How long an account's role is remembered before it is read again. */
const ROLE_TTL_MS = 15_000;

const LIKE = sequelize.getDialect() === 'postgres' ? Op.iLike : Op.like;

function table(name) {
  const model = modelForTable(name);
  if (!model) throw new HttpError(500, `The ${name} table is missing from the database.`);
  return model;
}

/** 'sales_manager' → 'Sales manager'. */
function titleOf(key) {
  const words = String(key).replace(/[_\-\s]+/g, ' ').trim();
  return words ? words.charAt(0).toUpperCase() + words.slice(1) : String(key);
}

// ── Pages and their actions ─────────────────────────────────────────────

/** Which action a request is. */
function actionOf(method, path) {
  const tail = String(path || '/').replace(/\/+$/, '') || '/';
  switch (String(method).toUpperCase()) {
    case 'GET':
    case 'HEAD':
    case 'OPTIONS':
      return tail === '/export' ? 'export' : 'view';
    case 'DELETE':
      return 'delete';
    case 'POST':
      if (tail === '/import') return 'import';
      if (tail === '/bulk-delete') return 'delete';
      return tail === '/' ? 'create' : 'edit';
    default:
      return 'edit';
  }
}

/** The actions a page's router has routes for; view always. */
function actionsOf(pageRouter) {
  const found = new Set(['view']);
  let nested = false;
  for (const layer of pageRouter?.stack ?? []) {
    const route = layer.route;
    if (!route) {
      // A router inside the router: its routes can't be told apart here.
      if (layer.handle?.stack) nested = true;
      continue;
    }
    const paths = Array.isArray(route.path) ? route.path : [route.path];
    for (const method of Object.keys(route.methods ?? {})) {
      if (method === '_all') {
        nested = true;
        continue;
      }
      for (const path of paths) found.add(actionOf(method, typeof path === 'string' ? path : '/*'));
    }
  }
  if (nested) for (const action of ['create', 'edit', 'delete']) found.add(action);
  return ACTIONS.filter((action) => found.has(action));
}

let pageList = null;

/** Every page behind sign-in, in the menu's order: { id, title, roles, export?, import?, actions }. */
function pages() {
  if (pageList) return pageList;
  const planned = catalog.pages ?? [];
  const routers = pageRouters();
  const order = new Map(planned.map((page, index) => [page.id, index]));
  // A page of the plan without a route file (it shows other pages' data) can only be viewed.
  // permissions.g.js gives a page 'all' when its tables' records belong to a person.
  const found = planned.map((page) => {
    const actions = actionsOf(routers.get(page.id));
    return { ...page, actions: Array.isArray(page.all) ? [...actions, 'all'] : actions };
  });
  for (const [id, pageRouter] of routers) {
    if (!order.has(id)) found.push({ id, title: titleOf(id), roles: [], actions: actionsOf(pageRouter) });
  }
  found.sort((a, b) => (order.get(a.id) ?? 1e9) - (order.get(b.id) ?? 1e9) || a.id.localeCompare(b.id));
  if (routers.size > 0) pageList = found;
  return found;
}

let knownKeys = null;

/** Every permission there is. */
function known() {
  if (knownKeys && pageList) return knownKeys;
  knownKeys = new Set([MANAGE]);
  for (const page of pages()) for (const action of page.actions) knownKeys.add(`${page.id}.${action}`);
  return knownKeys;
}

/** The plan's roles for a page's action; empty for every role. */
const plannedRoles = (page, action) => page[action] ?? page.roles ?? [];

// ── What is in the database ─────────────────────────────────────────────

/** { roles: Map key → { key, name, description }, grants: Map key → Set of permissions } */
let state = null;
let loading = null;

async function read() {
  const roles = new Map();
  for (const row of await table(ROLES).findAll({ raw: true, order: [['name', 'ASC']] })) {
    roles.set(row.role_key, { key: row.role_key, name: row.name, description: row.description ?? '' });
  }
  const grants = new Map();
  for (const row of await table(GRANTS).findAll({ raw: true })) {
    if (!grants.has(row.role_key)) grants.set(row.role_key, new Set());
    grants.get(row.role_key).add(row.permission);
  }
  return { roles, grants };
}

/** How many accounts have each role value: Map value ('' for none) → count. */
async function roleCounts() {
  const counts = new Map();
  if (!COLUMNS.role) return counts;
  const rows = await accounts().findAll({
    attributes: [[sequelize.col(COLUMNS.role), 'role'], [sequelize.fn('COUNT', sequelize.col(COLUMNS.id)), 'people']],
    group: [sequelize.col(COLUMNS.role)],
    raw: true,
  });
  for (const row of rows) {
    const key = row.role == null ? '' : String(row.role);
    counts.set(key, (counts.get(key) ?? 0) + Number(row.people));
  }
  return counts;
}

/**
 * Adds what the database has not seen yet: the plan's roles, the roles
 * accounts already have, and each new permission for the roles the plan
 * gives it to. What was seen before is left as the administrators set it,
 * a deleted role or an unticked permission included.
 */
async function seed() {
  const seeded = table(SEEDED);
  const done = new Set((await seeded.findAll({ raw: true })).map((row) => row.name));
  const existing = new Set((await table(ROLES).findAll({ raw: true })).map((row) => row.role_key));
  const counts = await roleCounts();
  const marks = [];
  const fresh = [];

  const wanted = new Set([...ADMIN_ROLES, ...(catalog.roles ?? []), DEFAULT_ROLE, ...counts.keys()]);
  for (const key of wanted) {
    if (!key || key.length > 64 || done.has(`role:${key}`)) continue;
    if (!existing.has(key)) {
      await table(ROLES).create({ role_key: key, name: titleOf(key).slice(0, 100) }, { hooks: false });
      existing.add(key);
      fresh.push(key);
    }
    marks.push(`role:${key}`);
  }

  const grants = [];
  for (const page of pages()) {
    for (const action of page.actions) {
      const permission = `${page.id}.${action}`;
      const isNew = !done.has(`perm:${permission}`);
      const roles = plannedRoles(page, action);
      for (const key of existing) {
        if (ADMIN_ROLES.has(key)) continue;
        if (!isNew && !fresh.includes(key)) continue;
        // Everyone's records go only to the roles named, never to every role.
        if (action === 'all' ? !roles.includes(key) : roles.length > 0 && !roles.includes(key)) continue;
        grants.push({ role_key: key, permission });
      }
      if (isNew) marks.push(`perm:${permission}`);
    }
  }
  if (grants.length > 0) await table(GRANTS).bulkCreate(grants, { ignoreDuplicates: true, hooks: false });
  if (marks.length > 0) {
    await seeded.bulkCreate(marks.map((name) => ({ name: name.slice(0, 190) })), { ignoreDuplicates: true, hooks: false });
  }

  // Nobody is an administrator yet: the account named in AppWand becomes one.
  if (FIRST_ADMIN && COLUMNS.role && ![...ADMIN_ROLES].some((key) => (counts.get(key) ?? 0) > 0)) {
    const row = await findByEmail(FIRST_ADMIN);
    if (row) {
      const role = [...ADMIN_ROLES][0];
      await accounts().update({ [COLUMNS.role]: role }, { where: { [COLUMNS.id]: row[COLUMNS.id] } });
      console.log(`[access-control] ${FIRST_ADMIN} is now "${role}"`);
    } else {
      console.warn(`[access-control] ACCESS_FIRST_ADMIN: no account has the email ${FIRST_ADMIN}`);
    }
  }
}

/** The roles and permissions, read (and seeded) the first time. */
function load() {
  if (state) return Promise.resolve(state);
  loading ??= (async () => {
    try {
      await seed();
      state = await read();
      return state;
    } finally {
      loading = null;
    }
  })();
  return loading;
}

async function reload() {
  state = await read();
  return state;
}

// ── Who may do what ─────────────────────────────────────────────────────

/** The role an account counts as. */
const effective = (role) => (role == null || role === '' ? DEFAULT_ROLE : String(role));

const isAdmin = (role) => ADMIN_ROLES.has(effective(role));

function can(role, permission) {
  const key = effective(role);
  if (ADMIN_ROLES.has(key)) return true;
  return state?.grants.get(key)?.has(permission) ?? false;
}

/** What the app is told an account may do (AuthState.can). */
function permissionsOf(role) {
  const key = effective(role);
  if (ADMIN_ROLES.has(key)) return [...known()];
  const all = known();
  return [...(state?.grants.get(key) ?? [])].filter((permission) => all.has(permission));
}

/** The role's name as the app shows it beside the signed-in person; undefined for an unknown role. */
const roleNameOf = (role) => state?.roles.get(effective(role))?.name;

/** Account id → { role, at }: the token's role may be days old. */
const recent = new Map();

/** The account's role as the database has it now; also put on req.user. */
async function roleFor(req) {
  const id = String(req.user.id);
  const hit = recent.get(id);
  let role;
  if (hit && Date.now() - hit.at < ROLE_TTL_MS) {
    role = hit.role;
  } else {
    const row = await findById(req.user.id);
    if (!row) throw unauthorized('This account no longer exists.');
    role = COLUMNS.role && row[COLUMNS.role] != null && row[COLUMNS.role] !== '' ? String(row[COLUMNS.role]) : null;
    if (recent.size > 5000) recent.clear();
    recent.set(id, { role, at: Date.now() });
  }
  req.user.role = role;
  return role;
}

function refusal(action) {
  switch (action) {
    case 'view':
      return forbidden('Your role cannot open this.');
    case 'create':
      return forbidden('Your role cannot add records here.');
    case 'delete':
      return forbidden('Your role cannot delete records here.');
    case 'export':
      return forbidden('Your role cannot export this list.');
    case 'import':
      return forbidden('Your role cannot import into this list.');
    default:
      return forbidden('Your role cannot change records here.');
  }
}

/** In front of a page's routes (routes/index.js), after requireAuth. */
function check(id, req, res, next) {
  (async () => {
    const role = await roleFor(req);
    await load();
    const action = actionOf(req.method, req.path);
    if (!can(role, `${id}.${action}`)) throw refusal(action);
  })().then(() => next(), next);
}

setAccess({ check, permissionsOf, roleNameOf, can, isAdmin });

// ── The Roles & permissions page's API ──────────────────────────────────

const present = (role, counts) => ({
  key: role.key,
  name: role.name,
  description: role.description,
  protected: ADMIN_ROLES.has(role.key),
  isDefault: role.key === DEFAULT_ROLE,
  people: (counts.get(role.key) ?? 0) + (role.key === DEFAULT_ROLE ? counts.get('') ?? 0 : 0),
  permissions: permissionsOf(role.key),
});

/** Only permissions there are; an action on a page brings the page's view with it. */
function clean(permissions) {
  const all = known();
  const kept = new Set(permissions.filter((permission) => all.has(permission)));
  for (const permission of [...kept]) {
    if (permission === MANAGE) continue;
    const view = `${permission.slice(0, permission.lastIndexOf('.'))}.view`;
    if (all.has(view)) kept.add(view);
  }
  return kept;
}

/** Makes [key]'s permissions [wanted], touching only the rows that differ. */
async function setGrants(key, wanted, transaction) {
  const model = table(GRANTS);
  const now = new Set((await model.findAll({ where: { role_key: key }, raw: true, transaction })).map((row) => row.permission));
  const gone = [...now].filter((permission) => !wanted.has(permission));
  const added = [...wanted].filter((permission) => !now.has(permission));
  if (gone.length > 0) await model.destroy({ where: { role_key: key, permission: { [Op.in]: gone } }, transaction });
  if (added.length > 0) await model.bulkCreate(added.map((permission) => ({ role_key: key, permission })), { transaction });
}

/** A key for a new role from its name: 'Sales Manager' → 'sales_manager'. */
function keyFor(name) {
  const base = name.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 56) || 'role';
  let key = base;
  for (let n = 2; state.roles.has(key); n += 1) key = `${base}_${n}`;
  return key;
}

const RoleInput = z.object({
  name: z.string().trim().min(1, 'Enter a name for the role.').max(100),
  description: z.string().trim().max(255).nullish(),
  permissions: z.array(z.string().max(160)).max(5000).optional(),
  copyFrom: z.string().max(64).optional(),
});

const RoleChanges = RoleInput.partial();

const PersonInput = z.object({ role: z.string().max(64).nullable() });

function roleOr404(key) {
  const role = state.roles.get(key);
  if (!role) throw notFound('This role no longer exists.');
  return role;
}

const router = Router();

router.use(requireAuth, asyncHandler(async (req, res, next) => {
  const role = await roleFor(req);
  await load();
  if (!can(role, MANAGE)) throw forbidden('Your role cannot manage roles and permissions.');
  next();
}));

// Everything the page shows but the people.
router.get('/meta', asyncHandler(async (req, res) => {
  const counts = await roleCounts();
  res.json({
    pages: pages().map((page) => ({ id: page.id, title: page.title, actions: page.actions })),
    roles: [...state.roles.values()].map((role) => present(role, counts)),
    defaultRole: DEFAULT_ROLE,
    canAssign: COLUMNS.role !== '',
    you: { id: req.user.id, admin: isAdmin(req.user.role) },
  });
}));

router.post('/roles', validate({ body: RoleInput }), asyncHandler(async (req, res) => {
  const { name, description, permissions, copyFrom } = req.body;
  const key = keyFor(name);
  const wanted = clean(permissions ?? (copyFrom && !ADMIN_ROLES.has(copyFrom) ? [...(state.grants.get(copyFrom) ?? [])] : []));
  await sequelize.transaction(async (transaction) => {
    await table(ROLES).create({ role_key: key, name, description: description || null }, { transaction });
    await setGrants(key, wanted, transaction);
    await table(SEEDED).bulkCreate([{ name: `role:${key}` }], { ignoreDuplicates: true, hooks: false, transaction });
  });
  await reload();
  res.status(201).json(present(state.roles.get(key), await roleCounts()));
}));

router.patch('/roles/:key', validate({ body: RoleChanges }), asyncHandler(async (req, res) => {
  const role = roleOr404(req.params.key);
  const { name, description, permissions } = req.body;
  await sequelize.transaction(async (transaction) => {
    const changes = {};
    if (name !== undefined) changes.name = name;
    if (description !== undefined) changes.description = description || null;
    if (Object.keys(changes).length > 0) await table(ROLES).update(changes, { where: { role_key: role.key }, transaction });
    // An administrator role has everything: there is nothing to tick.
    if (permissions !== undefined && !ADMIN_ROLES.has(role.key)) await setGrants(role.key, clean(permissions), transaction);
  });
  await reload();
  res.json(present(state.roles.get(role.key), await roleCounts()));
}));

// ?moveTo=<role key>: the role its people get.
router.delete('/roles/:key', asyncHandler(async (req, res) => {
  const role = roleOr404(req.params.key);
  if (ADMIN_ROLES.has(role.key)) throw badRequest('An administrator role cannot be deleted.');
  if (role.key === DEFAULT_ROLE) throw badRequest('This is the role of people without one, so it cannot be deleted.');
  const people = (await roleCounts()).get(role.key) ?? 0;
  const moveTo = typeof req.query.moveTo === 'string' ? req.query.moveTo : '';
  if (people > 0) {
    if (!moveTo || moveTo === role.key || !state.roles.has(moveTo)) throw badRequest('Choose the role its people get.');
    if (ADMIN_ROLES.has(moveTo) && !isAdmin(req.user.role)) throw forbidden('Only an administrator can make people administrators.');
  }
  await sequelize.transaction(async (transaction) => {
    if (people > 0) await accounts().update({ [COLUMNS.role]: moveTo }, { where: { [COLUMNS.role]: role.key }, transaction });
    await table(GRANTS).destroy({ where: { role_key: role.key }, transaction });
    await table(ROLES).destroy({ where: { role_key: role.key }, transaction });
  });
  recent.clear();
  await reload();
  res.status(204).end();
}));

const person = (row) => ({
  id: row[COLUMNS.id],
  name: row[COLUMNS.name],
  email: row[COLUMNS.email],
  role: COLUMNS.role && row[COLUMNS.role] != null && row[COLUMNS.role] !== '' ? String(row[COLUMNS.role]) : null,
});

// ?page, ?limit, ?search, ?role (a role key: the people who have it) and
// ?except (a role key: everyone else). People without a role count as the
// default role's.
router.get('/people', validate({ query: listQuery() }), asyncHandler(async (req, res) => {
  const { page, limit, search } = req.query;
  const all = [];
  if (search) {
    const like = { [LIKE]: `%${search}%` };
    all.push({ [Op.or]: [...new Set([COLUMNS.name, COLUMNS.email])].map((column) => ({ [column]: like })) });
  }
  const role = typeof req.query.role === 'string' ? req.query.role.trim() : '';
  const except = typeof req.query.except === 'string' ? req.query.except.trim() : '';
  if (COLUMNS.role) {
    const column = COLUMNS.role;
    // An ENUM column refuses a comparison with ''.
    const empty = accounts().rawAttributes?.[column]?.type?.key === 'ENUM' ? [] : [''];
    if (role) {
      all.push(role === DEFAULT_ROLE
        ? { [Op.or]: [{ [column]: [role, ...empty] }, { [column]: null }] }
        : { [column]: role });
    }
    if (except) {
      all.push(except === DEFAULT_ROLE
        ? { [column]: { [Op.notIn]: [except, ...empty] } }
        : { [Op.or]: [{ [column]: { [Op.ne]: except } }, { [column]: null }] });
    }
  }
  const { rows, count } = await accounts().findAndCountAll({
    where: all.length ? { [Op.and]: all } : {},
    order: [[COLUMNS.name, 'ASC'], [COLUMNS.id, 'ASC']],
    limit,
    offset: (page - 1) * limit,
    raw: true,
  });
  res.json({ items: rows.map(person), total: count });
}));

// { role }: a role key, or null for none.
router.patch('/people/:id', validate({ body: PersonInput }), asyncHandler(async (req, res) => {
  if (!COLUMNS.role) throw badRequest('The accounts table has no role column.');
  const role = req.body.role || null;
  if (role && !state.roles.has(role)) throw badRequest('This role no longer exists.');
  const row = await findById(req.params.id);
  if (!row) throw notFound('This account no longer exists.');
  // Nobody changes their own role, so the last administrator can't lock everyone out.
  if (String(row[COLUMNS.id]) === String(req.user.id)) throw badRequest('You cannot change your own role.');
  if ((isAdmin(row[COLUMNS.role]) || isAdmin(role)) && !isAdmin(req.user.role)) {
    throw forbidden('Only an administrator can change who is an administrator.');
  }
  try {
    await accounts().update({ [COLUMNS.role]: role }, { where: { [COLUMNS.id]: row[COLUMNS.id] } });
  } catch (err) {
    if (err?.name === 'SequelizeDatabaseError') {
      throw badRequest('The accounts table does not accept this role: its role column only allows fixed values.');
    }
    throw err;
  }
  recent.delete(String(row[COLUMNS.id]));
  res.json(person({ ...row, [COLUMNS.role]: role }));
}));

export default {
  id: 'access-control',
  mount(app) {
    app.use('/api/access', router);
    // A change made straight in the database is picked up within a minute.
    setInterval(() => {
      if (state) reload().catch(() => {});
    }, 60_000).unref();
  },
  /** server.js awaits this before listening, so the first sign-in already has its permissions. */
  async ready() {
    try {
      const { roles } = await load();
      console.log(`[access-control] ${roles.size} role${roles.size === 1 ? '' : 's'}, ${pages().length} page${pages().length === 1 ? '' : 's'}`);
    } catch (err) {
      console.error('[access-control] the roles could not be read:', err.message);
    }
  },
};
