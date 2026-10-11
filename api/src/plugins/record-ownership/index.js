// Record ownership: the rows of the tables ticked in AppWand belong to the
// account in their owner column, and a signed-in person only reaches their
// own. Nothing in a page's code: the models are narrowed here.
//
// For the person asking (req.user, kept for the request by request.js):
//   findAll, findOne, findByPk, findAndCountAll, count, sum, min, max,
//   Model.update, Model.destroy, increment / decrement and include only
//   reach their rows; create, bulkCreate and upsert fill the owner column
//   with their id, whatever was sent.
// Someone who manages everyone's records gets every row with the same code,
// and may give a record to someone else by sending the owner column.
//
// Who manages everyone's: with the Roles & permissions plugin, a role with
// '<page id>.all' on the page being asked (administrators always; set in the
// app); without it, the roles OWNERSHIP_ROLES names for the table
// ('orders:admin|manager,tasks:admin').
//
// Not narrowed: requests with nobody signed in, scheduled jobs, work inside
// asSystem(), and raw SQL (sequelize.query).
//
// Owned by AppWand: OWNERSHIP_TABLES, OWNERSHIP_COLUMNS and OWNERSHIP_ROLES
// in .env are set in AppWand (Plugins).
import { AsyncLocalStorage } from 'node:async_hooks';
import { getAccess } from '../../access.js';
import { forbidden } from '../../errors.js';
import { modelForTable, Op, sequelize } from '../../models/index.js';
import { currentRequest } from '../../request.js';

const list = (value) => String(value ?? '').split(',').map((item) => item.trim()).filter(Boolean);

const TABLES = new Set(list(process.env.OWNERSHIP_TABLES));

/** Table → the roles that reach everyone's records of it, without the Roles & permissions plugin. */
const ROLES = new Map();
for (const entry of list(process.env.OWNERSHIP_ROLES)) {
  const at = entry.indexOf(':');
  if (at > 0) ROLES.set(entry.slice(0, at).trim(), new Set(entry.slice(at + 1).split('|').map((role) => role.trim()).filter(Boolean)));
}

function tableOf(model) {
  const name = model.getTableName();
  return typeof name === 'string' ? name : name.tableName;
}

/** Table → its owner column, for the ticked tables the database has. */
const owners = new Map();
for (const pair of list(process.env.OWNERSHIP_COLUMNS)) {
  const at = pair.indexOf(':');
  if (at <= 0) continue;
  const table = pair.slice(0, at).trim();
  const column = pair.slice(at + 1).trim();
  if (!TABLES.has(table)) continue;
  if (modelForTable(table)?.rawAttributes[column]) owners.set(table, column);
  else console.warn(`[record-ownership] ${table}.${column} is missing from the database, so ${table} is not narrowed.`);
}

/** The owner column of a model's table; undefined when its rows belong to nobody. */
const ownerOf = (model) => (model && typeof model.getTableName === 'function' ? owners.get(tableOf(model)) : undefined);

const system = new AsyncLocalStorage();

/**
 * Runs [work] reaching every row, whoever is signed in: for the rare request
 * that must change another person's row as a side effect.
 *   await asSystem(() => Product.decrement('stock', { where: { id } }));
 */
export const asSystem = (work) => system.run(true, work);

/** The page a request is for: '/api/orders/5' → 'orders'. */
function pageOf(req) {
  const match = /^\/api\/([^/?]+)/.exec(req.baseUrl || '');
  return match ? match[1] : '';
}

function seesAll(req, table) {
  const access = getAccess();
  // Roles & permissions decides, per page; administrators have everything.
  if (typeof access?.can === 'function') return access.can(req.user.role, `${pageOf(req) || '-'}.all`);
  return ROLES.get(table)?.has(String(req.user.role ?? '')) ?? false;
}

/** Who is asking for [table]'s rows: { id, all }; null when nobody is (a job, sign-in, asSystem). */
function viewer(table) {
  if (system.getStore()) return null;
  const req = currentRequest();
  const id = req?.user?.id;
  if (id == null) return null;
  return { id, all: seesAll(req, table) };
}

const and = (where, extra) => (where ? { [Op.and]: [where, extra] } : extra);

/** Keeps a find, an update or a delete of many rows to the asker's own. */
function narrow(options, table, column) {
  const who = viewer(table);
  if (!who || who.all) return;
  options.where = and(options.where, { [column]: who.id });
}

/** The same for the owned tables a find joins in. */
function narrowIncludes(includes) {
  if (!Array.isArray(includes)) return;
  for (const include of includes) {
    if (!include || typeof include !== 'object') continue;
    const column = ownerOf(include.model);
    const who = column ? viewer(tableOf(include.model)) : null;
    if (who && !who.all) {
      include.where = and(include.where, { [column]: who.id });
      // Someone else's row is left out; the row that points at it stays.
      if (include.required === undefined) include.required = false;
    }
    narrowIncludes(include.include);
  }
}

/** A new row is the asker's, unless someone managing everyone's names an owner. */
function stamp(record, table, column, options) {
  const who = viewer(table);
  if (!who) return;
  if (!who.all || record.get(column) == null) record.set(column, who.id);
  if (Array.isArray(options?.fields) && !options.fields.includes(column)) options.fields.push(column);
}

const theirs = () => forbidden('This record belongs to someone else.');

/** A row about to be saved or deleted must be the asker's; they cannot give it away. */
function guard(record, table, column, saving) {
  const who = viewer(table);
  if (!who || who.all) return;
  const was = record.previous(column);
  // Read without its owner column: the find that read it was narrowed already.
  if (was === undefined) return;
  if (was === null || String(was) !== String(who.id)) throw theirs();
  if (saving && record.changed(column)) record.set(column, was);
}

function watch(model, table, column) {
  const name = 'appwand:ownership';
  model.addHook('beforeFind', name, (options) => narrow(options, table, column));
  model.addHook('beforeBulkUpdate', name, (options) => {
    const who = viewer(table);
    if (!who || who.all) return;
    options.where = and(options.where, { [column]: who.id });
    if (options.attributes && options.attributes[column] !== undefined) options.attributes[column] = who.id;
  });
  model.addHook('beforeBulkDestroy', name, (options) => narrow(options, table, column));
  model.addHook('beforeBulkRestore', name, (options) => narrow(options, table, column));
  // Before validation, so a column the database requires is already filled.
  model.addHook('beforeValidate', name, (record, options) => {
    if (record.isNewRecord) stamp(record, table, column, options);
  });
  model.addHook('beforeCreate', name, (record, options) => stamp(record, table, column, options));
  model.addHook('beforeBulkCreate', name, (records, options) => {
    for (const record of records) stamp(record, table, column, options);
  });
  model.addHook('beforeUpsert', name, (values) => {
    const who = viewer(table);
    if (who && (!who.all || values[column] == null)) values[column] = who.id;
  });
  model.addHook('beforeUpdate', name, (record) => guard(record, table, column, true));
  model.addHook('beforeDestroy', name, (record) => guard(record, table, column, false));

  // Totals run no hooks: count, sum, min and max all go through aggregate.
  const aggregate = model.aggregate;
  model.aggregate = function (attribute, fn, options) {
    const who = viewer(table);
    if (!who || who.all) return aggregate.call(this, attribute, fn, options);
    return aggregate.call(this, attribute, fn, { ...options, where: and(options?.where, { [column]: who.id }) });
  };
  // Nor do increment and decrement.
  const increment = model.increment;
  model.increment = function (fields, options) {
    const who = viewer(table);
    if (!who || who.all) return increment.call(this, fields, options);
    return increment.call(this, fields, { ...options, where: and(options?.where, { [column]: who.id }) });
  };
}

// At load, not in mount(): everything that reads the models is narrowed from the start.
for (const model of Object.values(sequelize.models)) {
  const column = ownerOf(model);
  if (column) watch(model, tableOf(model), column);
  // Any table may join an owned one in.
  if (owners.size > 0) {
    model.addHook('beforeFindAfterExpandIncludeAll', 'appwand:ownership', (options) => narrowIncludes(options.include));
  }
}

export default {
  id: 'record-ownership',
  mount() {
    const tables = [...owners.keys()].sort();
    console.log(`[record-ownership] people only reach their own records of: ${tables.join(', ') || 'no table'}`);
  },
};
