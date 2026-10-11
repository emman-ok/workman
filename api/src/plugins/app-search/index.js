// App search: the search box in the app's header. GET /api/app-search?q=text
// looks in the tables ticked in AppWand, in the columns chosen for each, and
// answers the records found, grouped by table, each with the app route that
// opens it.
//
// A table is only searched for someone who may open one of its pages
// (./pages.g.js, written by AppWand from the page plan): with the Roles &
// permissions plugin, a role with '<page id>.view'; without it, the page's
// roles. It is searched through its model, so the Record ownership plugin
// keeps people to their own records and the Soft delete plugin's trash is
// left out.
//
// Owned by AppWand: SEARCH_TABLES, SEARCH_FIELDS, SEARCH_TITLE,
// SEARCH_SUBTITLE, SEARCH_PHOTO and SEARCH_LIMIT in .env are set in AppWand (Plugins).
import { Router } from 'express';
import { getAccess } from '../../access.js';
import { asyncHandler } from '../../middleware/async.js';
import { requireAuth } from '../../middleware/auth.js';
import { modelForTable, Op, sequelize } from '../../models/index.js';
import pages from './pages.g.js';

const list = (value) => String(value ?? '').split(',').map((item) => item.trim()).filter(Boolean);

/** 'customers:first_name|last_name,orders:reference' → Map { customers → [first_name, last_name], orders → [reference] }. */
function perTable(value) {
  const columns = new Map();
  for (const entry of list(value)) {
    const at = entry.indexOf(':');
    if (at <= 0) continue;
    columns.set(entry.slice(0, at).trim(), entry.slice(at + 1).split('|').map((column) => column.trim()).filter(Boolean));
  }
  return columns;
}

const FIELDS = perTable(process.env.SEARCH_FIELDS);
const TITLE = perTable(process.env.SEARCH_TITLE);
const SUBTITLE = perTable(process.env.SEARCH_SUBTITLE);

/** Table → the column with the picture shown beside its results ('users:photo,products:image'). */
const PHOTO = perTable(process.env.SEARCH_PHOTO);

/** Records listed per table. */
const LIMIT = Math.min(20, Math.max(1, Math.floor(Number(process.env.SEARCH_LIMIT ?? 5)) || 5));

/** Shorter text is answered with nothing. */
const MIN_LENGTH = 2;
const MAX_LENGTH = 100;

/** Columns never searched or shown. */
const SECRET = /password|passwd|secret|token$|^hash$|_hash$/i;

/** Longer titles are cut. */
const MAX_TEXT = 120;

const POSTGRES = sequelize.getDialect() === 'postgres';

/**
 * What is searched: per ticked table its model, its key, the columns the text
 * is looked for in and the ones a result shows. A table the database lacks,
 * one without a single-column key and one with no column to search are left out.
 */
const sources = [];
for (const table of list(process.env.SEARCH_TABLES)) {
  const model = modelForTable(table);
  if (!model) {
    console.warn(`[app-search] the ${table} table is missing from the database, so it is not searched.`);
    continue;
  }
  const keys = model.primaryKeyAttributes;
  const has = (column) => Boolean(model.rawAttributes[column]) && !SECRET.test(column);
  const fields = (FIELDS.get(table) ?? []).filter(has);
  if (keys.length !== 1 || fields.length === 0) {
    console.warn(`[app-search] ${table} has ${keys.length !== 1 ? 'no single key column' : 'no field to search'}, so it is not searched.`);
    continue;
  }
  let title = (TITLE.get(table) ?? []).filter(has);
  if (title.length === 0) title = [fields[0]];
  let subtitle = (SUBTITLE.get(table) ?? []).filter(has);
  // A second line that only repeats the title says nothing.
  if (subtitle.join(',') === title.join(',')) subtitle = [];
  // The picture beside each result; null for a table without one.
  const photo = (PHOTO.get(table) ?? []).filter(has)[0] ?? null;
  sources.push({ table, model, key: keys[0], fields, title, subtitle, photo });
}

/** [column] contains the typed text. Postgres has no ILIKE for a number or an enum, so the column is read as text there. */
function contains(model, column, pattern) {
  if (!POSTGRES) return { [column]: { [Op.like]: pattern } };
  const field = model.rawAttributes[column].field ?? column;
  return sequelize.where(sequelize.cast(sequelize.col(`${model.name}.${field}`), 'TEXT'), { [Op.iLike]: pattern });
}

/** A value as a result shows it. */
function shown(value) {
  if (value == null) return '';
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? '' : value.toISOString().slice(0, 16).replace('T', ' ');
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'object') return '';
  return String(value).trim();
}

/** The values of [columns] that are not empty, joined with a space: first name + last name. */
function joined(row, columns) {
  const text = columns.map((column) => shown(row[column])).filter(Boolean).join(' ');
  return text.length > MAX_TEXT ? `${text.slice(0, MAX_TEXT)}…` : text;
}

/** Whether the person asking may open [page]. */
function allowed(req, page) {
  if (!page.auth) return true;
  const access = getAccess();
  // Roles & permissions decides, in the app; administrators have everything.
  if (typeof access?.can === 'function') return access.can(req.user.role, `${page.id}.view`);
  return page.roles.length === 0 || page.roles.includes(String(req.user.role ?? ''));
}

/** One table's results for the person asking; null when they may open none of its pages or nothing matches. */
async function search(req, source, pattern) {
  const entry = pages[source.table];
  const candidates = (entry?.pages ?? []).filter((page) => allowed(req, page));
  if (candidates.length === 0) return null;
  const rows = await source.model.findAll({
    attributes: [...new Set([source.key, ...source.title, ...source.subtitle, ...(source.photo ? [source.photo] : [])])],
    where: { [Op.or]: source.fields.map((column) => contains(source.model, column, pattern)) },
    order: [[source.title[0], 'ASC'], [source.key, 'ASC']],
    limit: LIMIT,
    raw: true,
  });
  if (rows.length === 0) return null;
  // The record's own page when they may open it, else the list it is in.
  const page = candidates[0];
  return {
    table: source.table,
    label: entry.label,
    items: rows.map((row) => {
      const id = row[source.key];
      return {
        id: String(id),
        title: joined(row, source.title) || `#${id}`,
        subtitle: joined(row, source.subtitle),
        // Only for a table with a photo column: the stored path or link, '' for a record without a picture.
        ...(source.photo ? { photo: row[source.photo] == null ? '' : String(row[source.photo]) } : {}),
        path: page.record ? page.route.replace(/:[A-Za-z_][A-Za-z0-9_]*/, encodeURIComponent(String(id))) : page.route,
        // A record's page opens over the page the person is on; a list replaces it.
        push: page.record,
      };
    }),
  };
}

const router = Router();
router.use(requireAuth);

// ?q=text → { groups: [{ table, label, items: [{ id, title, subtitle, photo?, path, push }] }] }, the tables in the order ticked.
router.get('/', asyncHandler(async (req, res) => {
  const term = String(req.query.q ?? '').trim().slice(0, MAX_LENGTH);
  if (term.length < MIN_LENGTH) return res.json({ groups: [] });
  const pattern = `%${term}%`;
  const groups = await Promise.all(sources.map(async (source) => {
    try {
      return await search(req, source, pattern);
    } catch (err) {
      // One table failing leaves the others' results.
      console.error(`[app-search] ${source.table} could not be searched:`, err.message);
      return null;
    }
  }));
  res.json({ groups: groups.filter(Boolean) });
}));

export default {
  id: 'app-search',
  mount(app) {
    app.use('/api/app-search', router);
    console.log(`[app-search] searching ${sources.map((source) => source.table).join(', ') || 'no table'}`);
  },
};
