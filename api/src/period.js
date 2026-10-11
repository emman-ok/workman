// The period a dashboard or a report shows, and the one before it. Owned by AppWand.
//
// The app sends the days picked in its date range control as
// ?from=2026-10-01&to=2026-10-11&tz=<minutes east of UTC>:
//
//   router.get('/', validate({ query: periodQuery }), asyncHandler(async (req, res) => {
//     const period = periodOf(req.query);
//     const [value, previous] = await Promise.all([
//       Orders.sum('total', { where: { created_at: period.current(Orders, 'created_at') } }),
//       Orders.sum('total', { where: { created_at: period.previous(Orders, 'created_at') } }),
//     ]);
//     const bucket = period.bucket(Orders, 'created_at');
//     const rows = await Orders.findAll({
//       attributes: [[bucket, 'bucket'], [fn('SUM', col('total')), 'total']],
//       where: { created_at: period.current(Orders, 'created_at') },
//       group: [bucket], order: [[bucket, 'ASC']], raw: true,
//     });
//     res.json({ sales: { value, previous }, byDay: period.fill(rows, 'bucket', { total: 0 }) });
//   }));
import { Op } from 'sequelize';
import sequelize from './db.js';
import { z } from './middleware/validate.js';

const DAY = 86400000;
const DAY_TEXT = /^\d{4}-\d{2}-\d{2}$/;

/** The query a period arrives as; other keys pass through, bad values fall back to the defaults. */
export const periodQuery = z.looseObject({
  from: z.string().regex(DAY_TEXT).optional().catch(undefined),
  to: z.string().regex(DAY_TEXT).optional().catch(undefined),
  tz: z.coerce.number().int().min(-840).max(840).catch(0),
});

// A day as the UTC midnight that carries its name, and back.
const stamp = (text) => {
  if (typeof text !== 'string' || !DAY_TEXT.test(text)) return null;
  const [year, month, day] = text.split('-').map(Number);
  const value = Date.UTC(year, month - 1, day);
  return Number.isFinite(value) ? value : null;
};
const name = (value) => new Date(value).toISOString().slice(0, 10);

// Whether the column holds a day (DATE) rather than a moment (DATETIME, TIMESTAMP).
const dayOnly = (model, column) => {
  const attribute = model?.rawAttributes?.[String(column).split('.').pop()];
  return attribute?.type?.key === 'DATEONLY';
};

/**
 * The period of a request: the days ?from to ?to, both included, in the time
 * zone of whoever asked; the last `days` (30) up to today when they are left
 * out. With it comes the period before, of the same length.
 *
 *   from, to                  the period as Dates: from its first moment up to, not including, `to`
 *   previousFrom, previousTo  the period before, the same way (previousTo is from)
 *   firstDay, lastDay         its first and last day, 'YYYY-MM-DD'
 *   days                      how many days it has
 *   unit                      'day', or 'month' for a period longer than 62 days: what a chart's points are
 *   current(model, column)    the where-value of rows in the period: where: { created_at: period.current(Orders, 'created_at') }
 *   previous(model, column)   the same for the period before
 *   bucket(model, column)     what to select and group by for a chart: the row's day 'YYYY-MM-DD' or month 'YYYY-MM'
 *   buckets                   every day (or month) of the period, in order
 *   fill(rows, key, blank)    a row per bucket, in order: the row whose [key] is the bucket, else { [key]: bucket, ...blank }
 *
 * `column` is the column's name, written 'Orders.created_at' in a query that joins another table.
 */
export function periodOf(query = {}, { days: length = 30 } = {}) {
  const tz = Math.max(-840, Math.min(840, Math.trunc(Number(query.tz)) || 0));
  const today = stamp(name(Date.now() + tz * 60000));
  let last = stamp(query.to) ?? today;
  let first = stamp(query.from) ?? last - (Math.max(1, length) - 1) * DAY;
  if (first > last) [first, last] = [last, first];
  // Ten years at most: a typed address cannot ask for a row per day of a century.
  first = Math.max(first, last - 3660 * DAY);

  const days = Math.round((last - first) / DAY) + 1;
  const end = last + DAY;
  const before = first - days * DAY;
  const unit = days > 62 ? 'month' : 'day';
  const moment = (value) => new Date(value - tz * 60000);

  const range = (model, column, start, stop) =>
    dayOnly(model, column)
      ? { [Op.gte]: name(start), [Op.lt]: name(stop) }
      : { [Op.gte]: moment(start), [Op.lt]: moment(stop) };

  const buckets = [];
  if (unit === 'day') {
    for (let value = first; value <= last; value += DAY) buckets.push(name(value));
  } else {
    const stop = new Date(last);
    for (const at = new Date(first); at.getUTCFullYear() * 12 + at.getUTCMonth() <= stop.getUTCFullYear() * 12 + stop.getUTCMonth();) {
      buckets.push(at.toISOString().slice(0, 7));
      at.setUTCDate(1);
      at.setUTCMonth(at.getUTCMonth() + 1);
    }
  }

  const bucket = (model, column) => {
    const quoted = sequelize.getQueryInterface().quoteIdentifiers(String(column));
    const shift = dayOnly(model, column) ? 0 : tz;
    switch (sequelize.getDialect()) {
      case 'postgres':
        return sequelize.literal(
          `to_char(${quoted}${shift === 0 ? '' : ` + interval '${shift} minutes'`}, '${unit === 'month' ? 'YYYY-MM' : 'YYYY-MM-DD'}')`,
        );
      case 'sqlite':
        return sequelize.literal(
          `strftime('${unit === 'month' ? '%Y-%m' : '%Y-%m-%d'}', ${quoted}${shift === 0 ? '' : `, '${shift >= 0 ? '+' : ''}${shift} minutes'`})`,
        );
      default:
        return sequelize.literal(
          `DATE_FORMAT(${quoted}${shift === 0 ? '' : ` + INTERVAL ${shift} MINUTE`}, '${unit === 'month' ? '%Y-%m' : '%Y-%m-%d'}')`,
        );
    }
  };

  const fill = (rows, key = 'bucket', blank = {}) => {
    const found = new Map();
    for (const row of rows ?? []) {
      const plain = typeof row?.get === 'function' ? row.get({ plain: true }) : row;
      if (plain && plain[key] != null) found.set(String(plain[key]), plain);
    }
    return buckets.map((value) => found.get(value) ?? { [key]: value, ...blank });
  };

  return {
    from: moment(first),
    to: moment(end),
    previousFrom: moment(before),
    previousTo: moment(first),
    firstDay: name(first),
    lastDay: name(last),
    days,
    unit,
    tz,
    buckets,
    current: (model, column) => range(model, column, first, end),
    previous: (model, column) => range(model, column, before, first),
    bucket,
    fill,
  };
}

export default periodOf;
