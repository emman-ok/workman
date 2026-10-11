// Exports of list pages as CSV or Excel files. Owned by AppWand.
//
//   router.get('/export', validate({ query: ListQuery }), asyncHandler(async (req, res) => {
//     await sendExport(req, res, { model: Orders, where, include, order });
//   }));
//
// The page gives the rows (the list route's where, include and order). The
// columns, their headings, the formats, the row limit and who may export are
// chosen in AppWand (exports.g.js), never in the page's code.
import { Op } from 'sequelize';
import { getAccess } from './access.js';
import { badRequest, forbidden, notFound } from './errors.js';
import { exportsConfig } from './exports.g.js';

/** Rows read from the database at a time. */
const BATCH = 500;

/** Columns never exported, whatever the settings say. */
const SECRET = /password|passwd|secret|token$|^hash$|_hash$/i;

const CONTENT_TYPES = {
  csv: 'text/csv; charset=utf-8',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

/** 'created_at' → 'Created at'. */
function heading(name) {
  const words = String(name).replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/[_.\s]+/g, ' ').trim().toLowerCase();
  return (words.charAt(0).toUpperCase() + words.slice(1)).replace(/\bid\b/g, 'ID');
}

function typeOf(attribute) {
  switch (attribute?.type?.key) {
    case 'BOOLEAN':
      return 'boolean';
    case 'INTEGER':
    case 'BIGINT':
    case 'DECIMAL':
    case 'FLOAT':
    case 'DOUBLE':
    case 'REAL':
      return 'number';
    case 'DATEONLY':
      return 'date';
    case 'DATE':
      return 'datetime';
    case 'JSON':
    case 'JSONB':
      return 'json';
    default:
      return 'text';
  }
}

/**
 * The columns of the file: the ones chosen in AppWand that the model still
 * has, or every column of the model. `category.name` reads the row the
 * `category` association points at.
 */
function columnsOf(model, config) {
  const wanted = Array.isArray(config.columns) && config.columns.length > 0
    ? config.columns
    : Object.keys(model.rawAttributes).map((field) => ({ field }));
  const columns = [];
  for (const { field, label } of wanted) {
    const [first, second, more] = String(field).split('.');
    if (more !== undefined || SECRET.test(second ?? first)) continue;
    if (second === undefined) {
      const attribute = model.rawAttributes[first];
      if (attribute) columns.push({ label: label || heading(first), type: typeOf(attribute), read: (row) => row[first] });
      continue;
    }
    const association = model.associations[first];
    const attribute = association?.target?.rawAttributes[second];
    if (!attribute || association.isMultiAssociation) continue;
    columns.push({
      alias: first,
      name: second,
      label: label || heading(`${first} ${second}`),
      type: typeOf(attribute),
      read: (row) => row[first]?.[second],
    });
  }
  return columns;
}

const aliasOf = (entry) => (typeof entry === 'string' ? entry : entry?.as ?? entry?.association?.as ?? entry?.association);

/** The page's includes, plus the associations the columns read. */
function joinsFor(include, columns) {
  const joins = (Array.isArray(include) ? include : [include]).filter(Boolean);
  const needed = new Map();
  for (const column of columns) {
    if (column.alias) needed.set(column.alias, [...(needed.get(column.alias) ?? []), column.name]);
  }
  for (const [alias, names] of needed) {
    const at = joins.findIndex((entry) => aliasOf(entry) === alias);
    if (at < 0) {
      joins.push({ association: alias, attributes: names, required: false });
    } else if (typeof joins[at] === 'object' && Array.isArray(joins[at].attributes)) {
      joins[at] = { ...joins[at], attributes: [...new Set([...joins[at].attributes, ...names])] };
    }
  }
  return joins;
}

/** [['name', 'ASC']] from whatever the page orders its list by. */
function orderOf(order, key) {
  let list = Array.isArray(order) ? order : [];
  if (list.length === 2 && typeof list[0] === 'string' && /^(asc|desc)$/i.test(String(list[1]))) list = [list];
  return key ? [...list, [key, 'ASC']] : list;
}

/**
 * A cell that would run as a formula when the file is opened in a
 * spreadsheet gets a leading apostrophe. Signed numbers and phone numbers
 * (+234 801 234 5678) stay as they are.
 */
function safeText(text) {
  if (/^[=@\t\r]/.test(text)) return `'${text}`;
  if (/^[+-]/.test(text) && !/^[+-][\d\s().-]*$/.test(text)) return `'${text}`;
  return text;
}

/** A column's value of a row, as a CSV string or an Excel cell value. */
function cellOf(column, row, { excel, minutes }) {
  const raw = column.read(row);
  if (raw === null || raw === undefined) return excel ? null : '';
  switch (column.type) {
    case 'boolean':
      return [true, 1, '1', 'true'].includes(raw) ? 'Yes' : 'No';
    case 'number': {
      const number = Number(raw);
      const exact = Number.isFinite(number) && (!Number.isInteger(number) || Number.isSafeInteger(number));
      return excel && exact ? number : String(raw);
    }
    case 'date': {
      const day = raw instanceof Date ? raw.toISOString().slice(0, 10) : String(raw).slice(0, 10);
      if (!excel) return day;
      const date = new Date(`${day}T00:00:00Z`);
      return Number.isNaN(date.getTime()) ? day : date;
    }
    case 'datetime': {
      const date = raw instanceof Date ? raw : new Date(raw);
      if (Number.isNaN(date.getTime())) return String(raw);
      // In the time zone of whoever asked: the app sends its offset as ?tz=<minutes>.
      const local = new Date(date.getTime() + minutes * 60_000);
      return excel ? local : local.toISOString().slice(0, 19).replace('T', ' ');
    }
    case 'json':
      return typeof raw === 'string' ? raw : JSON.stringify(raw);
    default: {
      const text = typeof raw === 'object' ? JSON.stringify(raw) : String(raw);
      return excel ? text.slice(0, 32767) : safeText(text);
    }
  }
}

function fileName(config, page, format) {
  const base = String(config.fileName || page).replace(/[^\w.-]+/g, '-').replace(/^-+|-+$/g, '') || 'export';
  const day = config.dateInName === false ? '' : `-${new Date().toISOString().slice(0, 10)}`;
  return `${base}${day}.${format}`;
}

async function writeCsv(res, columns, rows, { delimiter, minutes }) {
  const quote = (text) => (text.includes(delimiter) || /["\r\n]|^\s|\s$/.test(text) ? `"${text.replaceAll('"', '""')}"` : text);
  // The byte order mark makes Excel read the file as UTF-8.
  res.write(`﻿${columns.map((column) => quote(column.label)).join(delimiter)}\r\n`);
  for await (const batch of rows) {
    const lines = batch.map((row) => columns.map((column) => quote(cellOf(column, row, { excel: false, minutes }))).join(delimiter));
    if (lines.length > 0) res.write(`${lines.join('\r\n')}\r\n`);
  }
  res.end();
}

const WIDTHS = { boolean: 10, number: 14, date: 14, datetime: 20, json: 40, text: 28 };
const DATE_FORMATS = { date: 'yyyy-mm-dd', datetime: 'yyyy-mm-dd hh:mm' };

async function writeExcel(ExcelJS, res, columns, rows, { title, minutes }) {
  const workbook = new ExcelJS.stream.xlsx.WorkbookWriter({ stream: res, useStyles: true });
  const name = String(title).replace(/[\[\]:*?/\\]/g, ' ').trim().slice(0, 31) || 'Export';
  const sheet = workbook.addWorksheet(name, { views: [{ state: 'frozen', ySplit: 1 }] });
  sheet.columns = columns.map((column) => ({
    header: column.label,
    width: Math.max(WIDTHS[column.type] ?? 28, column.label.length + 4),
    style: DATE_FORMATS[column.type] ? { numFmt: DATE_FORMATS[column.type] } : {},
  }));
  sheet.getRow(1).font = { bold: true };
  sheet.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: columns.length } };
  for await (const batch of rows) {
    for (const row of batch) sheet.addRow(columns.map((column) => cellOf(column, row, { excel: true, minutes }))).commit();
  }
  await workbook.commit();
}

/**
 * Answers GET /export of a list page with its rows as a file: ?format=csv|xlsx,
 * the list's own search, filters and sort (the page passes its where, include
 * and order), ?ids=1,2,3 for the selected rows only, ?tz=<minutes> for the
 * times. The headers X-Export-Rows and X-Export-Total say how many rows went
 * in and how many there are.
 */
export async function sendExport(req, res, { model, where = {}, include = [], order = [] } = {}) {
  const page = req.baseUrl.split('/').filter(Boolean).pop();
  const config = exportsConfig[page];
  if (!config || !model) throw notFound('This list cannot be exported.');
  // With the Roles & permissions plugin, the page's guard has already checked '<page>.export'.
  if (!getAccess() && config.roles?.length > 0 && !config.roles.includes(req.user?.role)) throw forbidden('Your role cannot export this list.');
  const format = String(req.query.format || config.formats[0]).toLowerCase();
  if (!config.formats.includes(format) || !CONTENT_TYPES[format]) {
    throw badRequest(`This list is exported as ${config.formats.join(' or ')}.`);
  }
  const columns = columnsOf(model, config);
  if (columns.length === 0) throw badRequest('This export has no columns. Choose them in AppWand.');

  const minutes = Math.max(-840, Math.min(840, Number(req.query.tz) || 0));
  const key = model.primaryKeyAttribute;
  const ids = String(req.query.ids ?? '').split(',').map((id) => id.trim()).filter(Boolean).slice(0, 1000);
  const filter = ids.length > 0 && key ? { [Op.and]: [where, { [key]: ids }] } : where;
  const joins = joinsFor(include, columns);
  const sorted = orderOf(order, key);

  const total = await model.count({ where: filter, include: joins, ...(key ? { distinct: true } : {}) });
  if (total === 0) throw badRequest('There is nothing to export.');
  const limit = Math.min(total, Number(config.maxRows) > 0 ? Number(config.maxRows) : 5000);
  const load = async (offset) => {
    const found = await model.findAll({ where: filter, include: joins, order: sorted, limit: Math.min(BATCH, limit - offset), offset });
    return found.map((row) => row.get({ plain: true }));
  };
  // Everything that can fail with a readable answer happens before the first byte.
  const first = await load(0);
  const ExcelJS = format === 'xlsx' ? (await import('exceljs')).default : null;
  async function* rows() {
    yield first;
    for (let offset = BATCH; offset < limit && first.length === BATCH; offset += BATCH) {
      const batch = await load(offset);
      yield batch;
      if (batch.length < BATCH) return;
    }
  }

  res.status(200);
  res.setHeader('Content-Type', CONTENT_TYPES[format]);
  res.setHeader('Content-Disposition', `attachment; filename="${fileName(config, page, format)}"`);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Export-Rows', String(limit));
  res.setHeader('X-Export-Total', String(total));
  try {
    if (format === 'xlsx') await writeExcel(ExcelJS, res, columns, rows(), { title: config.title || page, minutes });
    else await writeCsv(res, columns, rows(), { delimiter: config.delimiter || ',', minutes });
  } catch (err) {
    // The file is already on its way: cut it short rather than end it as if whole.
    console.error(err);
    res.destroy(err);
  }
}

export default sendExport;
