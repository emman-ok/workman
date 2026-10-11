// Mounts every page's route file: src/routes/<page id>.js -> /api/<page id>,
// behind the sign-in and roles the page plan gives it (../access.g.js).
// With the Roles & permissions plugin, what each role may do is kept in the
// database instead and checked per request (../access.js).
// Each file default-exports an express Router. Owned by AppWand.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { Router } from 'express';
import access from '../access.g.js';
import { getAccess, notePage } from '../access.js';
import { requireAuth, requireRole } from '../middleware/auth.js';

const dir = path.dirname(fileURLToPath(import.meta.url));
const router = Router();

function guards(id, pageRouter) {
  const rule = access[id];
  if (!rule) return [];
  const roles = rule.roles ?? [];
  if (!rule.auth && roles.length === 0) return [];
  notePage(id, pageRouter);
  const byRole = roles.length > 0 ? requireRole(...roles) : (req, res, next) => next();
  const permitted = (req, res, next) => {
    const managed = getAccess();
    return managed ? managed.check(id, req, res, next) : byRole(req, res, next);
  };
  return [requireAuth, permitted];
}

for (const file of fs.readdirSync(dir).sort()) {
  if (file === 'index.js' || !file.endsWith('.js')) continue;
  const id = file.slice(0, -3);
  try {
    const mod = await import(pathToFileURL(path.join(dir, file)).href);
    router.use(`/${id}`, ...guards(id, mod.default), mod.default);
  } catch (err) {
    console.error(`[routes] ${file} failed to load`);
    throw err;
  }
}

export default router;
