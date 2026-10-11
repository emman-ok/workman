// Request validation with Zod (https://zod.dev). Owned by AppWand.
//
//   router.post('/', validate({ body: OrderInput }), asyncHandler(async (req, res) => { ... req.body ... }));
//
// validate({ params, query, body }) parses those parts of the request and
// replaces them with the parsed values: trimmed, coerced, defaults filled and
// unknown keys dropped. A failure answers 400 { message, errors: { field: message } }
// through errors.js, as does any schema.parse(...) that throws inside a route.
import { z, ZodError } from 'zod';

export { z };

const count = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

// Plain-sentence messages for the common checks; a schema's own message
// (z.string().min(1, 'Pick a name.')) always wins over these.
z.config({
  customError: (issue) => {
    if (issue.code !== 'custom' && (issue.input === undefined || issue.input === null)) return 'Required';
    switch (issue.code) {
      case 'invalid_type':
        if (issue.expected === 'number' || issue.expected === 'int') return 'Must be a number';
        if (issue.expected === 'date') return 'Must be a valid date';
        if (issue.expected === 'boolean') return 'Must be true or false';
        return `Must be a ${issue.expected}`;
      case 'too_small':
        if (issue.origin === 'string') return issue.minimum === 1 ? 'Required' : `Must be at least ${count(issue.minimum, 'character')}`;
        if (issue.origin === 'array' || issue.origin === 'set') return `Must have at least ${count(issue.minimum, 'item')}`;
        return issue.inclusive ? `Must be at least ${issue.minimum}` : `Must be more than ${issue.minimum}`;
      case 'too_big':
        if (issue.origin === 'string') return `Must be at most ${count(issue.maximum, 'character')}`;
        if (issue.origin === 'array' || issue.origin === 'set') return `Must have at most ${count(issue.maximum, 'item')}`;
        return issue.inclusive ? `Must be at most ${issue.maximum}` : `Must be less than ${issue.maximum}`;
      case 'invalid_format':
        return issue.format === 'email' ? 'Must be a valid email address' : `Must be a valid ${issue.format}`;
      case 'invalid_value':
        return `Must be one of: ${issue.values.join(', ')}`;
      default:
        return undefined;
    }
  },
});

const label = (key) => {
  const words = key.replace(/_id$/, '').replace(/[_.]+/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2').trim().toLowerCase();
  return words.charAt(0).toUpperCase() + words.slice(1);
};

/** { field: 'Readable sentence.' } for a ZodError, first problem per field. */
export function fieldErrors(err) {
  const errors = {};
  for (const issue of err.issues) {
    const key = issue.path.join('.') || '_';
    if (key in errors) continue;
    const message = issue.message;
    if (key === '_' || /[.!?]$/.test(message)) errors[key] = message;
    else if (message === 'Required') errors[key] = `${label(key)} is required.`;
    else if (message.startsWith('Must ')) errors[key] = `${label(key)} ${message.charAt(0).toLowerCase()}${message.slice(1)}.`;
    else errors[key] = `${label(key)}: ${message}.`;
  }
  return errors;
}

const asSchema = (schema) => (schema instanceof z.ZodType ? schema : z.object(schema));

/**
 * Middleware that validates req.params, req.query and req.body. Each is a Zod
 * schema or a plain object of field schemas (wrapped in z.object).
 */
export function validate(schemas) {
  const parts = ['params', 'query', 'body'].filter((part) => schemas[part]).map((part) => [part, asSchema(schemas[part])]);
  return (req, res, next) => {
    (async () => {
      for (const [part, schema] of parts) {
        const value = await schema.parseAsync(req[part] ?? {});
        // Defined, not assigned: req.query is a getter in Express 5.
        Object.defineProperty(req, part, { value, writable: true, configurable: true, enumerable: true });
      }
    })().then(() => next(), next);
  };
}

/**
 * An optional column: '' and null become null (clears it), a missing key
 * stays missing (left alone on update). optional(z.coerce.number().min(0))
 */
export const optional = (schema) => z.preprocess((value) => (value === '' ? null : value), schema.nullish());

/**
 * The list conventions (?page, ?limit, ?search, ?sort, ?order) as a query
 * schema. Bad values fall back to the defaults instead of failing; other
 * query keys (filters) are kept as strings for the route to check.
 *   validate({ query: listQuery(['name', 'created_at'], { sort: 'created_at', order: 'desc' }) })
 */
export function listQuery(sortable = [], defaults = {}) {
  return z.looseObject({
    page: z.coerce.number().int().min(1).catch(1),
    limit: z.coerce.number().int().min(1).max(100).catch(defaults.limit ?? 20),
    search: z.string().trim().optional().catch(undefined).transform((value) => value || undefined),
    sort: sortable.length > 0 ? z.enum(sortable).catch(defaults.sort ?? sortable[0]) : z.string().optional().catch(undefined),
    order: z.enum(['asc', 'desc']).catch(defaults.order ?? 'asc'),
  });
}

export default validate;
