import jwt from 'jsonwebtoken';
import { forbidden, unauthorized } from '../errors.js';

function readUser(req) {
  const header = req.headers.authorization || '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) return null;
  try {
    const payload = jwt.verify(match[1], process.env.JWT_SECRET);
    return { id: payload.id, email: payload.email, name: payload.name, role: payload.role ?? null };
  } catch {
    return null;
  }
}

/** 401 unless a valid bearer token is present; sets req.user = { id, email, name, role }. */
export function requireAuth(req, res, next) {
  const user = readUser(req);
  if (!user) return next(unauthorized());
  req.user = user;
  next();
}

/** Sets req.user when a valid token is present, and carries on either way. */
export function optionalAuth(req, res, next) {
  req.user = readUser(req);
  next();
}

/** After requireAuth: 403 unless req.user.role is one of [roles]. */
export function requireRole(...roles) {
  const allowed = new Set(roles.flat());
  return (req, res, next) => {
    if (!req.user) return next(unauthorized());
    if (allowed.size > 0 && !allowed.has(req.user.role)) return next(forbidden('Your role cannot use this.'));
    next();
  };
}

export default requireAuth;
