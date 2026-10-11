import { DatabaseError, ForeignKeyConstraintError, UniqueConstraintError, ValidationError } from 'sequelize';
import { ZodError } from 'zod';
import { fieldErrors } from './middleware/validate.js';

export class HttpError extends Error {
  /** [errors]: { field: message }, answered beside the message like a validation error's. */
  constructor(status, message, errors) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

export const badRequest = (message = 'Bad request') => new HttpError(400, message);
export const unauthorized = (message = 'Sign in required') => new HttpError(401, message);
export const forbidden = (message = 'Not allowed') => new HttpError(403, message);
export const notFound = (message = 'Not found') => new HttpError(404, message);

const MISSING = new Set(['ER_BAD_NULL_ERROR', 'ER_NO_DEFAULT_FOR_FIELD', '23502']);
const WRONG_TYPE = new Set(['ER_TRUNCATED_WRONG_VALUE', 'ER_TRUNCATED_WRONG_VALUE_FOR_FIELD', 'WARN_DATA_TRUNCATED', '22P02', '22007', '22008']);
const TOO_LONG = new Set(['ER_DATA_TOO_LONG', '22001']);

function validationMessage(err) {
  const messages = (err.errors || []).map((e) => (e.type === 'notNull Violation' ? `${e.path} is required.` : e.message));
  return messages.length > 0 ? messages.join(' ') : 'Some fields are not valid.';
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json(err.errors ? { message: err.message, errors: err.errors } : { message: err.message });
  }
  // validate(...) and any schema.parse(...) in a route: 400 with one message
  // per field as well as the whole.
  if (err instanceof ZodError) {
    const errors = fieldErrors(err);
    return res.status(400).json({ message: Object.values(errors).join(' '), errors });
  }
  // UniqueConstraintError is a ValidationError, so it goes first.
  if (err instanceof UniqueConstraintError) {
    return res.status(409).json({ message: 'A record with the same unique value already exists.' });
  }
  if (err instanceof ForeignKeyConstraintError) {
    return res.status(409).json({ message: 'This record is linked to other records, or points at one that does not exist.' });
  }
  if (err instanceof ValidationError) {
    return res.status(400).json({ message: validationMessage(err) });
  }
  if (err instanceof DatabaseError) {
    const code = err.original?.code ?? err.parent?.code;
    if (MISSING.has(code)) return res.status(400).json({ message: 'A required field is missing.' });
    if (WRONG_TYPE.has(code)) return res.status(400).json({ message: 'A field has a value of the wrong type.' });
    if (TOO_LONG.has(code)) return res.status(400).json({ message: 'A value is too long for its field.' });
  }
  if (err && err.type === 'entity.parse.failed') {
    return res.status(400).json({ message: 'The request body is not valid JSON.' });
  }
  console.error(err);
  res.status(500).json({ message: 'Something went wrong on the server.' });
}
