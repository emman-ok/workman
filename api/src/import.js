// Imports of CSV or Excel files into a list page's table. Owned by AppWand.
//
//   router.post('/import', importFile, asyncHandler(async (req, res) => {
//     await runImport(req, res, { model: Orders });
//   }));
//
// The page gives the model (and, for a list of the signed-in person's own
// rows, where and values). The columns, their headings, the file types, what
// happens to rows already in the table, the row limit and who may import are
// chosen in AppWand (imports.g.js), never in the page's code.
import multer from 'multer';
import { ForeignKeyConstraintError, Op, UniqueConstraintError, ValidationError, col, fn, where as sqlWhere } from 'sequelize';
import { getAccess } from './access.js';
import { HttpError, badRequest, forbidden, notFound } from './errors.js';
import { importsConfig } from './imports.g.js';
import { withRequest } from './request.js';

const MAX_MB = Number(process.env.IMPORT_MAX_MB || 10);

/** Rows written, and values looked up, at a time. */
const BATCH = 500;

/** Rows with a problem named in the answer; the count is always whole. */
const MAX_ERRORS = 50;

/** Columns never imported, whatever the settings say. */
const SECRET = /password|passwd|secret|token$|^hash$|_hash$/i;

const FORMAT_NAMES = { csv: 'CSV (.csv)', xlsx: 'Excel (.xlsx)' };

/** The page's import settings, refused to a role that may not import. */
function configOf(req) {
  const page = req.baseUrl.split('/').filter(Boolean).pop();
  const config = importsConfig[page];
  if (!config) throw notFound('This list takes no imports.');
  // With the Roles & permissions plugin, the page's guard has already checked '<page>.import'.
  if (!getAccess() && config.roles?.length > 0 && !config.roles.includes(req.user?.role)) throw forbidden('Your role cannot import into this list.');
  return config;
}

const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: MAX_MB * 1024 * 1024, files: 1 } });

/** Route middleware: reads the uploaded file (form field "file") into req.file. */
export function importFile(req, res, next) {
  try {
    configOf(req);
  } catch (err) {
    return next(err);
  }
  upload.single('file')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      return next(err.code === 'LIMIT_FILE_SIZE' ? new HttpError(413, `The file is larger than ${MAX_MB} MB.`) : badRequest(err.message));
    }
    if (err) return next(err);
    // multer loses the request's context: put it back, so record events and
    // the audit log still know who is importing.
    withRequest(req, res, next);
  });
}

/** 'created_at' → 'Created at'. */
function heading(name) {
  const words = String(name).replace(/([a-z0-9])([A-Z])/g, '$1 $2').replace(/[_.\s]+/g, ' ').trim().toLowerCase();
  return (words.charAt(0).toUpperCase() + words.slice(1)).replace(/\bid\b/g, 'ID');
}

/** How a heading is compared: 'Unit Price', 'unit_price' and 'unitprice' are one. */
const norm = (text) => String(text ?? '').normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');

const namesOf = (...names) => new Set(names.flatMap((name) => (name ? [norm(name), norm(heading(name))] : [])).filter(Boolean));

/** A cell as trimmed text; '' when empty. */
function textOf(raw) {
  if (raw === null || raw === undefined) return '';
  if (raw instanceof Date) return Number.isNaN(raw.getTime()) ? '' : raw.toISOString().slice(0, 19).replace('T', ' ').replace(/ 00:00:00$/, '');
  return String(raw).trim();
}

const clip = (text) => (text.length > 60 ? `${text.slice(0, 60)}…` : text);

function typeOf(attribute) {
  switch (attribute?.type?.key) {
    case 'BOOLEAN':
      return 'boolean';
    case 'INTEGER':
    case 'BIGINT':
      return 'integer';
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
    case 'ENUM':
      return 'enum';
    case 'BLOB':
      return 'blob';
    default:
      return 'text';
  }
}

const YES = new Set(['yes', 'y', 'true', 't', '1', 'on']);
const NO = new Set(['no', 'n', 'false', 'f', '0', 'off']);

const fail = (message) => {
  throw new Error(message);
};

/** yyyy-mm-dd of a real day, or nothing. */
function dayOf(year, month, day) {
  const date = new Date(Date.UTC(year, month - 1, day));
  const real = date.getUTCFullYear() === Number(year) && date.getUTCMonth() === month - 1 && date.getUTCDate() === Number(day);
  return real ? date.toISOString().slice(0, 10) : null;
}

/**
 * A cell that is not empty as the column's value. Throws the rest of a
 * sentence that starts with the column's heading ("is not a number").
 */
function parse(type, raw, attribute, minutes) {
  const text = textOf(raw);
  switch (type) {
    case 'boolean': {
      if (typeof raw === 'boolean') return raw;
      const word = text.toLowerCase();
      if (YES.has(word)) return true;
      if (NO.has(word)) return false;
      return fail('must be Yes or No');
    }
    case 'integer':
    case 'number': {
      let digits = text.replace(/[\s ]/g, '');
      // 1,234.50 (thousands), then 12,5 (a decimal comma).
      if (/^[+-]?\d{1,3}(,\d{3})+(\.\d+)?$/.test(digits)) digits = digits.replaceAll(',', '');
      else if (/^[+-]?\d+,\d+$/.test(digits)) digits = digits.replace(',', '.');
      if (!/^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(digits)) return fail('is not a number');
      const whole = /^[+-]?\d+$/.test(digits);
      if (type === 'integer' && !whole) return Number.isInteger(Number(digits)) ? Number(digits) : fail('must be a whole number');
      // Kept as written, so a long decimal or a big id loses nothing.
      return typeof raw === 'number' ? raw : digits.replace(/^\+/, '');
    }
    case 'date': {
      if (raw instanceof Date) return raw.toISOString().slice(0, 10);
      const parts = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T].*)?$/.exec(text);
      return (parts && dayOf(parts[1], parts[2], parts[3])) || fail('is not a date (write it as 2026-01-31)');
    }
    case 'datetime': {
      // A time without a zone is the clock of whoever imports: the app sends its offset as ?tz=<minutes>.
      if (raw instanceof Date) return new Date(raw.getTime() - minutes * 60_000);
      const parts = /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?$/.exec(text);
      if (parts && dayOf(parts[1], parts[2], parts[3])) {
        const [hour, minute, second] = [Number(parts[4] ?? 0), Number(parts[5] ?? 0), Number(parts[6] ?? 0)];
        if (hour < 24 && minute < 60 && second < 60) {
          return new Date(Date.UTC(parts[1], parts[2] - 1, parts[3], hour, minute, second) - minutes * 60_000);
        }
      }
      const zoned = /(z|[+-]\d{2}:?\d{2})$/i.test(text) ? new Date(text) : null;
      return zoned && !Number.isNaN(zoned.getTime()) ? zoned : fail('is not a date and time (write it as 2026-01-31 14:30)');
    }
    case 'enum': {
      const values = attribute?.type?.values ?? [];
      const match = values.find((value) => String(value).toLowerCase() === text.toLowerCase());
      return match ?? fail(`must be one of: ${values.join(', ')}`);
    }
    case 'json': {
      if (typeof raw !== 'string') return raw;
      try {
        return JSON.parse(text);
      } catch {
        return fail('is not valid JSON');
      }
    }
    default: {
      // The apostrophe an export puts before a cell a spreadsheet would run as a formula.
      const value = /^'[=+\-@]/.test(text) ? text.slice(1) : text;
      const length = attribute?.type?.options?.length ?? attribute?.type?._length;
      if (Number(length) > 0 && value.length > Number(length)) return fail(`is longer than ${length} characters`);
      return value;
    }
  }
}

/**
 * What the file can fill: the columns chosen in AppWand that the model still
 * has, or every column of the model. `category.name` finds the row of the
 * `category` association with that name and fills its foreign key. `forced`
 * are the columns the page sets itself.
 */
function targetsOf(model, config, forced) {
  const wanted = Array.isArray(config.columns) && config.columns.length > 0
    ? config.columns
    : Object.keys(model.rawAttributes).map((field) => ({ field }));
  const targets = [];
  for (const { field, label } of wanted) {
    const [first, second, more] = String(field).split('.');
    if (more !== undefined || SECRET.test(second ?? first)) continue;
    if (second === undefined) {
      const attribute = model.rawAttributes[first];
      const type = typeOf(attribute);
      if (!attribute || attribute.autoIncrement || type === 'blob' || first in forced) continue;
      targets.push({ label: label || heading(first), names: namesOf(label, first), sets: first, attribute, type });
      continue;
    }
    const association = model.associations[first];
    const attribute = association?.target?.rawAttributes[second];
    if (!attribute || association.associationType !== 'BelongsTo' || association.foreignKey in forced) continue;
    const type = typeOf(attribute);
    targets.push({
      label: label || heading(`${first} ${second}`),
      names: namesOf(label, `${first} ${second}`, field),
      sets: association.foreignKey,
      lookup: { model: association.target, column: second, key: association.targetKey, type, text: type === 'text' || type === 'enum' },
    });
  }
  // A linked column goes last, so it wins over the foreign key's own column.
  return [...targets.filter((target) => !target.lookup), ...targets.filter((target) => target.lookup)];
}

/** The column that tells which rows of the file are already in the table. */
function keyOf(model, config) {
  if (config.mode !== 'update' && config.mode !== 'skip') return null;
  const name = String(config.matchBy || model.primaryKeyAttribute || '');
  const attribute = model.rawAttributes[name];
  if (!attribute || SECRET.test(name)) return null;
  const label = config.matchLabel || heading(name);
  return { name, label, attribute, type: typeOf(attribute), names: namesOf(label, name), primary: name === model.primaryKeyAttribute };
}

function decode(buffer) {
  if (buffer[0] === 0xff && buffer[1] === 0xfe) return new TextDecoder('utf-16le').decode(buffer.subarray(2));
  if (buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf) return buffer.subarray(3).toString('utf8');
  const text = buffer.toString('utf8');
  if (!text.includes('�')) return text;
  // Not UTF-8: a CSV saved by an older spreadsheet, in the Western European code page.
  try {
    return new TextDecoder('windows-1252').decode(buffer);
  } catch {
    return buffer.toString('latin1');
  }
}

/** The separator the file uses: the one its first line has most of. */
function delimiterOf(line) {
  let best = ',';
  let most = 0;
  for (const candidate of [',', ';', '\t', '|']) {
    let count = 0;
    let quoted = false;
    for (const ch of line) {
      if (ch === '"') quoted = !quoted;
      else if (ch === candidate && !quoted) count++;
    }
    if (count > most) [best, most] = [candidate, count];
  }
  return best;
}

function readCsv(buffer) {
  let text = decode(buffer);
  let delimiter = null;
  // Excel's own first line naming the separator.
  const hint = /^sep=(.)\r?\n/i.exec(text);
  if (hint) {
    delimiter = hint[1];
    text = text.slice(hint[0].length);
  }
  delimiter ??= delimiterOf(text.slice(0, text.search(/\r|\n|$/)));
  const lines = [];
  let cells = [];
  let cell = '';
  let quoted = false;
  let number = hint ? 2 : 1;
  let started = number;
  const end = () => {
    cells.push(cell);
    lines.push({ number: started, cells });
    cells = [];
    cell = '';
  };
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') {
        cell += '"';
        i++;
      } else if (ch === '"') {
        quoted = false;
      } else {
        if (ch === '\n') number++;
        cell += ch;
      }
    } else if (ch === '"' && cell === '') {
      quoted = true;
    } else if (ch === delimiter) {
      cells.push(cell);
      cell = '';
    } else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      end();
      number++;
      started = number;
    } else {
      cell += ch;
    }
  }
  if (cell !== '' || cells.length > 0) end();
  return lines;
}

/** What a cell of a workbook holds: a formula's result, a link's text, plain rich text. */
function plain(value) {
  if (value === null || value === undefined) return null;
  if (value instanceof Date || typeof value !== 'object') return value;
  if ('formula' in value || 'sharedFormula' in value || 'result' in value) return plain(value.result ?? null);
  if (Array.isArray(value.richText)) return value.richText.map((part) => part.text).join('');
  if ('text' in value) return plain(value.text);
  if ('error' in value) return null;
  return String(value);
}

async function readExcel(buffer) {
  const ExcelJS = (await import('exceljs')).default;
  const workbook = new ExcelJS.Workbook();
  try {
    await workbook.xlsx.load(buffer);
  } catch {
    throw badRequest('The file could not be read as an Excel workbook.');
  }
  // The first sheet with anything on it.
  const sheet = workbook.worksheets.find((candidate) => candidate.actualRowCount > 0) ?? workbook.worksheets[0];
  const lines = [];
  sheet?.eachRow({ includeEmpty: false }, (row, number) => {
    const cells = [];
    row.eachCell({ includeEmpty: false }, (cell, column) => {
      cells[column - 1] = plain(cell.value);
    });
    lines.push({ number, cells });
  });
  return lines;
}

/** The file's headings and the rows under them, each with its number in the file. */
async function readTable(file, config) {
  const buffer = file.buffer;
  if (!buffer || buffer.length === 0) throw badRequest('The file is empty.');
  if (buffer[0] === 0xd0 && buffer[1] === 0xcf) {
    throw badRequest('Old Excel files (.xls) cannot be read. Save the file as .xlsx or .csv and choose it again.');
  }
  const workbook = buffer[0] === 0x50 && buffer[1] === 0x4b;
  const format = workbook ? 'xlsx' : 'csv';
  if (!config.formats.includes(format)) {
    throw badRequest(`This list takes ${config.formats.map((name) => FORMAT_NAMES[name] ?? name).join(' or ')} files.`);
  }
  const lines = workbook ? await readExcel(buffer) : readCsv(buffer);
  const filled = lines.filter((line) => line.cells.some((cell) => textOf(cell) !== ''));
  if (filled.length === 0) throw badRequest('The file is empty.');
  const [head, ...rows] = filled;
  return { headings: Array.from(head.cells, textOf), rows };
}

/** The rows a linked column names, by their name (lower case for text) → their key. */
async function lookUp(target, rows) {
  const { model, column, key, type, text } = target.lookup;
  const wanted = new Set();
  for (const row of rows) {
    const value = textOf(row.cells[target.at]);
    if (value === '') continue;
    if (text) wanted.add(value.toLowerCase());
    else if (type === 'date' || type === 'datetime' || /^[+-]?\d+(\.\d+)?$/.test(value)) wanted.add(value);
  }
  const found = new Map();
  const all = [...wanted];
  for (let i = 0; i < all.length; i += BATCH) {
    const chunk = all.slice(i, i + BATCH);
    const matches = await model.findAll({
      attributes: [...new Set([key, column])],
      where: text ? sqlWhere(fn('lower', col(column)), { [Op.in]: chunk }) : { [column]: chunk },
      raw: true,
    });
    for (const match of matches) {
      const name = text ? String(match[column]).toLowerCase() : textOf(match[column]);
      if (!found.has(name)) found.set(name, match[key]);
    }
  }
  return found;
}

/** Why the database refused a row, in words. */
function reason(err) {
  if (err instanceof UniqueConstraintError) {
    const field = Object.keys(err.fields ?? {})[0];
    return field && !/\s/.test(field) ? `${heading(field)} is already used by another row.` : 'A row with the same unique value already exists.';
  }
  if (err instanceof ForeignKeyConstraintError) return 'It points at a row that does not exist.';
  if (err instanceof ValidationError) {
    const messages = (err.errors || []).map((e) => (e.type === 'notNull Violation' ? `${heading(e.path)} is required.` : e.message));
    if (messages.length > 0) return messages.join(' ');
  }
  return err?.original?.sqlMessage || err?.original?.message || err?.message || 'The row could not be saved.';
}

/**
 * Answers POST /import of a list page (after importFile): reads the CSV or
 * Excel file, matches its first row to the columns chosen in AppWand, and
 * adds or updates the rows.
 *
 *   model   the list's model.
 *   where   for a list that shows only some rows (the signed-in person's):
 *           the rows an import may update or skip.
 *   values  columns set on every row whatever the file says ({ user_id: req.user.id }).
 *
 * ?check=1 only reads the file and answers what would happen; ?tz=<minutes>
 * is the clock of the times in it. The answer:
 * { check, imported, total, created, updated, skipped, failed, errors: [{ row, message }], ignored: [heading] }.
 */
export async function runImport(req, res, { model, where = {}, values = {} } = {}) {
  const config = configOf(req);
  if (!model) throw notFound('This list takes no imports.');
  if (!req.file) throw badRequest('Choose a file to import (form field "file").');
  const check = ['1', 'true'].includes(String(req.query.check ?? ''));
  const minutes = Math.max(-840, Math.min(840, Number(req.query.tz) || 0));

  const { headings, rows } = await readTable(req.file, config);
  if (rows.length === 0) throw badRequest('The file has headings but no rows under them.');
  const limit = Number(config.maxRows) > 0 ? Number(config.maxRows) : 5000;
  if (rows.length > limit) throw badRequest(`The file has ${rows.length} rows. At most ${limit} can be imported at a time: split it.`);

  // Which column of the file fills what.
  const targets = targetsOf(model, config, values);
  const key = keyOf(model, config);
  const names = headings.map(norm);
  const taken = new Set();
  for (const target of targets) {
    target.at = names.findIndex((name, at) => name !== '' && !taken.has(at) && target.names.has(name));
    if (target.at >= 0) taken.add(target.at);
  }
  const used = targets.filter((target) => target.at >= 0);
  if (key) key.at = names.findIndex((name) => name !== '' && key.names.has(name));
  if (used.length === 0) {
    throw badRequest(`None of the file's columns match. Its first row should have these headings: ${targets.map((target) => target.label).join(', ')}.`);
  }
  if (key && key.at < 0 && !key.primary) {
    throw badRequest(`The file has no "${key.label}" column, which tells the rows already in the list from the new ones.`);
  }
  const ignored = headings.filter((name, at) => name !== '' && !taken.has(at) && at !== key?.at);

  // What a new row cannot go without.
  const required = Object.entries(model.rawAttributes)
    .filter(([name, attribute]) => attribute.allowNull === false && attribute.defaultValue === undefined && !attribute.autoIncrement && !(name in values))
    .map(([name]) => name);
  const labelOf = (name) => targets.find((target) => target.sets === name)?.label ?? heading(name);
  if (!key) {
    const missing = required.filter((name) => !used.some((target) => target.sets === name));
    if (missing.length > 0) {
      throw badRequest(`The file has no ${missing.map((name) => `"${labelOf(name)}"`).join(', ')} column${missing.length === 1 ? '' : 's'}.`);
    }
  }

  for (const target of used) {
    if (target.lookup) target.found = await lookUp(target, rows);
  }

  // Every row read first: nothing is written while reading.
  const plans = rows.map((row) => {
    const plan = { number: row.number, values: {}, problems: [], action: 'fail' };
    for (const target of used) {
      const raw = row.cells[target.at];
      const text = textOf(raw);
      // An empty cell leaves the column alone: the database's default for a new row, the value it has for an old one.
      if (text === '') continue;
      if (target.lookup) {
        const id = target.found.get(target.lookup.text ? text.toLowerCase() : text);
        if (id === undefined) plan.problems.push(`${target.label}: "${clip(text)}" was not found.`);
        else plan.values[target.sets] = id;
        continue;
      }
      try {
        plan.values[target.sets] = parse(target.type, raw, target.attribute, minutes);
      } catch (err) {
        plan.problems.push(`${target.label} ${err.message}.`);
      }
    }
    plan.filled = Object.keys(plan.values).length;
    if (key && key.at >= 0 && textOf(row.cells[key.at]) !== '') {
      try {
        plan.key = parse(key.type, row.cells[key.at], key.attribute, minutes);
      } catch (err) {
        if (!used.some((target) => target.at === key.at)) plan.problems.push(`${key.label} ${err.message}.`);
      }
    }
    Object.assign(plan.values, values);
    return plan;
  });

  // The rows already in the table, by the matching column.
  const keyText = (value) => textOf(value).toLowerCase();
  const existing = new Map();
  if (key) {
    const wanted = [...new Map(plans.filter((plan) => plan.key !== undefined).map((plan) => [keyText(plan.key), plan.key])).values()];
    // Text is matched whatever its capitals, on every database.
    const loose = key.type === 'text' || key.type === 'enum';
    for (let i = 0; i < wanted.length; i += BATCH) {
      const chunk = wanted.slice(i, i + BATCH);
      const match = loose
        ? sqlWhere(fn('lower', col(key.name)), { [Op.in]: chunk.map((value) => String(value).toLowerCase()) })
        : { [key.name]: chunk };
      const found = await model.findAll({ where: { [Op.and]: [where, match] } });
      for (const row of found) existing.set(keyText(row.get(key.name)), row);
    }
  }

  const seen = new Map();
  for (const plan of plans) {
    let old;
    if (plan.key !== undefined) {
      const text = keyText(plan.key);
      if (seen.has(text)) plan.problems.push(`It has the same ${key.label} as row ${seen.get(text)}.`);
      else seen.set(text, plan.number);
      old = existing.get(text);
    }
    if (plan.problems.length > 0) continue;
    if (old) {
      plan.existing = old;
      plan.action = config.mode === 'skip' ? 'skip' : 'update';
      delete plan.values[model.primaryKeyAttribute];
      continue;
    }
    if (plan.key !== undefined) {
      if (key.primary && key.attribute.autoIncrement) {
        plan.problems.push(`There is no row with ${key.label} ${textOf(plan.key)}. Leave it empty to add a row.`);
        continue;
      }
      if (!(key.name in values)) plan.values[key.name] = plan.key;
    } else if (plan.filled === 0) {
      plan.problems.push('It has nothing in the columns that are imported.');
      continue;
    }
    const missing = required.filter((name) => plan.values[name] === undefined || plan.values[name] === null);
    if (missing.length > 0) {
      plan.problems.push(`${missing.map(labelOf).join(', ')} ${missing.length === 1 ? 'is' : 'are'} required.`);
      continue;
    }
    plan.action = 'create';
  }

  const count = (action) => plans.filter((plan) => plan.action === action).length;
  const errors = plans.filter((plan) => plan.action === 'fail').map((plan) => ({ row: plan.number, message: plan.problems.join(' ') }));
  const answer = (result) => {
    errors.sort((a, b) => a.row - b.row);
    res.json({
      check,
      total: plans.length,
      skipped: count('skip'),
      ...result,
      failed: errors.length,
      errors: errors.slice(0, MAX_ERRORS),
      ignored,
    });
  };
  // With "all or nothing", a row with a problem stops the whole file.
  if (check || (config.allOrNothing && errors.length > 0)) {
    return answer({ imported: false, created: count('create'), updated: count('update') });
  }

  const done = { created: 0, updated: 0 };
  if (config.allOrNothing) {
    const transaction = await model.sequelize.transaction();
    let current = plans[0];
    try {
      for (const plan of plans) {
        current = plan;
        if (plan.action === 'create') {
          await model.create(plan.values, { transaction });
          done.created++;
        } else if (plan.action === 'update') {
          await plan.existing.update(plan.values, { transaction });
          done.updated++;
        }
      }
      await transaction.commit();
    } catch (err) {
      await transaction.rollback().catch(() => {});
      errors.push({ row: current.number, message: reason(err) });
      return answer({ imported: false, created: 0, updated: 0 });
    }
    return answer({ imported: true, ...done });
  }

  const refuse = (plan, err) => {
    plan.action = 'fail';
    errors.push({ row: plan.number, message: reason(err) });
  };
  const creates = plans.filter((plan) => plan.action === 'create');
  for (let i = 0; i < creates.length; i += BATCH) {
    // One insert per set of columns, so a column a row leaves out keeps the database's default.
    const groups = new Map();
    for (const plan of creates.slice(i, i + BATCH)) {
      const fields = Object.keys(plan.values).sort();
      const group = groups.get(fields.join('|')) ?? { fields, plans: [] };
      group.plans.push(plan);
      groups.set(fields.join('|'), group);
    }
    for (const group of groups.values()) {
      try {
        await model.bulkCreate(group.plans.map((plan) => plan.values), { fields: group.fields });
        done.created += group.plans.length;
      } catch {
        // One row was refused: one at a time, to find it and keep the others.
        for (const plan of group.plans) {
          try {
            await model.create(plan.values);
            done.created++;
          } catch (err) {
            refuse(plan, err);
          }
        }
      }
    }
  }
  for (const plan of plans) {
    if (plan.action !== 'update') continue;
    try {
      await plan.existing.update(plan.values);
      done.updated++;
    } catch (err) {
      refuse(plan, err);
    }
  }
  answer({ imported: true, ...done });
}

export default runImport;
