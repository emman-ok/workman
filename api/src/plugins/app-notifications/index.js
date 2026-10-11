// In-app notifications: the bell in the app's header. GET /api/app-notifications
// answers the latest records of the tables ticked in AppWand as notifications,
// newest first, with how many are unread; POST /read and /read-all mark them
// read in the table's read column.
//
// Whose they are: a table with a "whose it is" column gives each person only
// their own rows. Without one, a table's rows go to the people who may open
// one of its pages (./pages.g.js, written by AppWand from the page plan: with
// the Roles & permissions plugin, a role with '<page id>.view'; without it,
// the page's roles), or to everyone signed in when no page shows it. Tables
// are read through their models, so the Record ownership plugin keeps people
// to their own records and the Soft delete plugin's trash is left out.
//
// Read and unread: a table with a read column keeps it in the database. One
// without is unread while its time is after ?since=, the time the app last
// showed the panel (kept on the device).
//
// Owned by AppWand: the NOTIFICATIONS_* values in .env are set in AppWand (Plugins).
import { Router } from 'express';
import { getAccess } from '../../access.js';
import { notFound } from '../../errors.js';
import { asyncHandler } from '../../middleware/async.js';
import { requireAuth } from '../../middleware/auth.js';
import { validate, z } from '../../middleware/validate.js';
import { modelForTable, Op } from '../../models/index.js';
import pages from './pages.g.js';

const list = (value) => String(value ?? '').split(',').map((item) => item.trim()).filter(Boolean);

/** 'tasks:title|status,orders:reference' → Map { tasks → [title, status], orders → [reference] }. */
function perTable(value) {
  const columns = new Map();
  for (const entry of list(value)) {
    const at = entry.indexOf(':');
    if (at <= 0) continue;
    columns.set(entry.slice(0, at).trim(), entry.slice(at + 1).split('|').map((column) => column.trim()).filter(Boolean));
  }
  return columns;
}

const TITLE = perTable(process.env.NOTIFICATIONS_TITLE);
const DETAIL = perTable(process.env.NOTIFICATIONS_DETAIL);
const IMAGE = perTable(process.env.NOTIFICATIONS_IMAGE);
const TIME = perTable(process.env.NOTIFICATIONS_TIME);
const USER = perTable(process.env.NOTIFICATIONS_USER);
const READ = perTable(process.env.NOTIFICATIONS_READ);

/** What a text or number read column is set to, and what it holds while unread (empty: anything else). */
const READ_VALUE = String(process.env.NOTIFICATIONS_READ_VALUE ?? '').trim() || 'read';
const UNREAD_VALUE = String(process.env.NOTIFICATIONS_UNREAD_VALUE ?? '').trim();

/** Notifications listed. */
const LIMIT = Math.min(50, Math.max(5, Math.floor(Number(process.env.NOTIFICATIONS_LIMIT ?? 20)) || 20));

/** Columns never shown. */
const SECRET = /password|passwd|secret|token$|^hash$|_hash$/i;

/** Longer texts are cut. */
const MAX_TITLE = 120;
const MAX_DETAIL = 240;

const NUMBERS = new Set(['INTEGER', 'BIGINT', 'SMALLINT', 'TINYINT', 'MEDIUMINT', 'FLOAT', 'DOUBLE', 'DECIMAL', 'REAL']);

/** How a read column says "read": a flag set to true, a date set to now, or a number or text set to the read value. */
function kindOf(type) {
  const key = String(type?.key ?? type ?? '').toUpperCase();
  if (key === 'BOOLEAN') return 'flag';
  if (key === 'DATE' || key === 'DATEONLY') return 'date';
  return NUMBERS.has(key) ? 'number' : 'text';
}

/**
 * The tables notifications come from: per ticked table its model, its key and
 * the columns chosen for it. A table the database lacks, one without a
 * single-column key and one with no title are left out.
 */
const sources = [];
for (const table of list(process.env.NOTIFICATIONS_TABLES)) {
  const model = modelForTable(table);
  if (!model) {
    console.warn(`[app-notifications] the ${table} table is missing from the database, so it gives no notifications.`);
    continue;
  }
  const keys = model.primaryKeyAttributes;
  const has = (column) => Boolean(column) && Boolean(model.rawAttributes[column]) && !SECRET.test(column);
  const one = (columns) => (columns.get(table) ?? []).filter(has)[0] ?? null;
  const title = (TITLE.get(table) ?? []).filter(has);
  if (keys.length !== 1 || title.length === 0) {
    console.warn(`[app-notifications] ${table} has ${keys.length !== 1 ? 'no single key column' : 'no title field'}, so it gives no notifications.`);
    continue;
  }
  const read = one(READ);
  const kind = read ? kindOf(model.rawAttributes[read].type) : null;
  const number = (value, otherwise) => (value !== '' && Number.isFinite(Number(value)) ? Number(value) : otherwise);
  sources.push({
    table,
    model,
    key: keys[0],
    title,
    detail: (DETAIL.get(table) ?? []).filter(has),
    image: one(IMAGE),
    time: one(TIME),
    user: one(USER),
    read,
    kind,
    // What the read column is set to, and what it holds while unread (null: anything else).
    readValue: kind === 'number' ? number(READ_VALUE, 1) : READ_VALUE,
    unreadValue: kind === 'number' ? number(UNREAD_VALUE, null) : UNREAD_VALUE || null,
  });
}

/** The rows of [source] not read yet, for a table with a read column. */
function unreadWhere(source) {
  const column = source.read;
  if (source.kind === 'flag') return { [Op.or]: [{ [column]: false }, { [column]: null }] };
  if (source.kind === 'date') return { [column]: null };
  if (source.unreadValue != null) return { [column]: source.unreadValue };
  return { [Op.or]: [{ [column]: { [Op.ne]: source.readValue } }, { [column]: null }] };
}

function isRead(source, row) {
  const value = row[source.read];
  if (source.kind === 'flag') return value === true || value === 1 || value === '1';
  if (source.kind === 'date') return value != null;
  if (source.unreadValue != null) return String(value ?? '') !== String(source.unreadValue);
  return String(value ?? '') === String(source.readValue);
}

/** What marking a row read writes. */
function readPatch(source) {
  if (source.kind === 'flag') return { [source.read]: true };
  if (source.kind === 'date') return { [source.read]: new Date() };
  return { [source.read]: source.readValue };
}

function toDate(value) {
  if (value == null || value === '') return null;
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

/** A value as a notification shows it. */
function shown(value) {
  if (value == null) return '';
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? '' : value.toISOString().slice(0, 16).replace('T', ' ');
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'object') return '';
  return String(value).trim();
}

function joined(row, columns, separator, max) {
  const text = columns.map((column) => shown(row[column])).filter(Boolean).join(separator);
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

/** Whether the person asking may open [page]. */
function allowed(req, page) {
  if (!page.auth) return true;
  const access = getAccess();
  // Roles & permissions decides, in the app; administrators have everything.
  if (typeof access?.can === 'function') return access.can(req.user.role, `${page.id}.view`);
  return page.roles.length === 0 || page.roles.includes(String(req.user.role ?? ''));
}

/**
 * The rows of [source] the person asking gets, and the page one opens; null
 * when they get none. Their own rows whatever the pages, or else every row
 * when they may open one of the table's pages (or no page shows it).
 */
function scope(req, source) {
  const entry = pages[source.table];
  const open = (entry?.pages ?? []).filter((page) => allowed(req, page));
  if (source.user) return { where: { [source.user]: req.user.id }, page: open[0] ?? null };
  if (entry && open.length === 0) return null;
  return { where: {}, page: open[0] ?? null };
}

/** One table's latest notifications and how many are unread, for the person asking. */
async function feed(req, source, since) {
  const mine = scope(req, source);
  if (!mine) return { items: [], unread: 0 };
  const { model, key } = source;
  const page = mine.page;
  const columns = [key, ...source.title, ...source.detail, source.time, source.image, source.read].filter(Boolean);
  const rows = await model.findAll({
    attributes: [...new Set(columns)],
    where: mine.where,
    order: source.time ? [[source.time, 'DESC'], [key, 'DESC']] : [[key, 'DESC']],
    limit: LIMIT,
    raw: true,
  });
  // Without a read column, a row is unread while it is newer than the last look at the panel.
  const byTime = !source.read && source.time && since;
  let unread = 0;
  if (source.read) {
    unread = await model.count({ where: { [Op.and]: [mine.where, unreadWhere(source)] } });
  } else if (byTime) {
    unread = await model.count({ where: { [Op.and]: [mine.where, { [source.time]: { [Op.gt]: since } }] } });
  }
  const items = rows.map((row) => {
    const id = row[key];
    const time = source.time ? toDate(row[source.time]) : null;
    return {
      key: `${source.table}:${id}`,
      table: source.table,
      id: String(id),
      title: joined(row, source.title, ' ', MAX_TITLE) || `#${id}`,
      detail: joined(row, source.detail, ' • ', MAX_DETAIL),
      image: source.image ? shown(row[source.image]) || null : null,
      time: time ? time.toISOString() : null,
      read: source.read ? isRead(source, row) : !(byTime && time && time > since),
      // Whether reading it is kept in the database.
      tracked: Boolean(source.read),
      // The record's own page when they may open it, else the list it is in; null when no page shows the table.
      path: !page ? null : page.record ? page.route.replace(/:[A-Za-z_][A-Za-z0-9_]*/, encodeURIComponent(String(id))) : page.route,
      // A record's page opens over the page the person is on; a list replaces it.
      push: Boolean(page?.record),
    };
  });
  return { items, unread };
}

const router = Router();
router.use(requireAuth);

// ?since=<ISO time> → { items: [{ key, table, id, title, detail, image, time, read, tracked, path, push }], unread, now }
router.get('/', asyncHandler(async (req, res) => {
  const since = toDate(typeof req.query.since === 'string' ? req.query.since : null);
  const feeds = await Promise.all(sources.map(async (source) => {
    try {
      return await feed(req, source, since);
    } catch (err) {
      // One table failing leaves the others' notifications.
      console.error(`[app-notifications] ${source.table} could not be read:`, err.message);
      return { items: [], unread: 0 };
    }
  }));
  const items = feeds
    .flatMap((one) => one.items)
    // Newest first; the ones without a time last.
    .sort((a, b) => (b.time ?? '').localeCompare(a.time ?? ''))
    .slice(0, LIMIT);
  res.json({
    items,
    unread: feeds.reduce((sum, one) => sum + one.unread, 0),
    // The API's clock: what the app keeps as "last looked" for the tables without a read column.
    now: new Date().toISOString(),
  });
}));

// { table, id } → marks that row read. A table without a read column has nothing to write.
router.post('/read', validate({ body: z.object({ table: z.string().min(1), id: z.union([z.string().min(1), z.number()]) }) }), asyncHandler(async (req, res) => {
  const source = sources.find((one) => one.table === req.body.table);
  const mine = source ? scope(req, source) : null;
  if (!source || !mine) throw notFound('Notification not found.');
  if (!source.read) return res.json({ read: false });
  // Through the row, so record events and the audit log see the change.
  const row = await source.model.findOne({ where: { [Op.and]: [mine.where, { [source.key]: req.body.id }] } });
  if (!row) throw notFound('Notification not found.');
  if (!isRead(source, row)) await row.update(readPatch(source));
  res.json({ read: true });
}));

// Marks every unread row of the person asking read, in the tables with a read column.
router.post('/read-all', asyncHandler(async (req, res) => {
  let updated = 0;
  for (const source of sources) {
    const mine = source.read ? scope(req, source) : null;
    if (!mine) continue;
    try {
      const [count] = await source.model.update(readPatch(source), { where: { [Op.and]: [mine.where, unreadWhere(source)] } });
      updated += Number(count) || 0;
    } catch (err) {
      console.error(`[app-notifications] ${source.table} could not be marked read:`, err.message);
    }
  }
  res.json({ updated });
}));

export default {
  id: 'app-notifications',
  mount(app) {
    app.use('/api/app-notifications', router);
    console.log(`[app-notifications] notifying from ${sources.map((source) => source.table).join(', ') || 'no table'}`);
  },
};
