// Entry point. Owned by AppWand: pages add routes under src/routes/, not here.
import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import compression from 'compression';
import { rateLimit } from 'express-rate-limit';
import { errorHandler } from './errors.js';
import { changePassword, currentUser, updateProfile } from './auth/accounts.js';
import { asyncHandler } from './middleware/async.js';
import { requireAuth } from './middleware/auth.js';
import uploadsRouter, { filesRouter } from './uploads/router.js';
import { plugins } from './plugins.g.js';
import { startAutomations, withRequest } from './automations.js';
import routes from './routes/index.js';

const app = express();
app.disable('x-powered-by');
// Behind a reverse proxy (nginx, a hosting platform), TRUST_PROXY is the
// number of proxies in front, so req.ip and the rate limits see the client.
const trustProxy = Number(process.env.TRUST_PROXY || 0);
if (trustProxy > 0) app.set('trust proxy', trustProxy);

app.use(compression());
// The export headers say how many rows a file holds (export.js); a browser
// shows a page only the headers named here.
app.use(cors({ origin: process.env.CORS_ORIGIN || '*', exposedHeaders: ['X-Export-Rows', 'X-Export-Total'] }));

// Rate limits per client address, answering 429 { message } like any other
// error. The counts live in memory, one set per process. 0 turns one off.
const limiter = (minutes, limit, message, options = {}) =>
  rateLimit({ windowMs: minutes * 60_000, limit, standardHeaders: 'draft-8', legacyHeaders: false, message: { message }, ...options });
const perMinute = Number(process.env.RATE_LIMIT_PER_MINUTE ?? 300);
if (perMinute > 0) {
  app.use('/api', limiter(1, perMinute, 'Too many requests. Try again in a minute.', { skip: (req) => req.path === '/health' }));
}
// Sign-in, registration and password resets: failed attempts only, so a
// user who signs in fine is never held back.
const authAttempts = Number(process.env.AUTH_RATE_LIMIT ?? 20);
if (authAttempts > 0) {
  app.use('/api/auth', limiter(15, authAttempts, 'Too many attempts. Try again in 15 minutes.', {
    skip: (req) => req.method === 'GET',
    skipSuccessfulRequests: true,
  }));
}
// Asking for a one-time code (sign in with a code, Forgot password): every
// request counts, because each may send an email or a text message.
const codeRequests = Number(process.env.CODE_RATE_LIMIT ?? 5);
if (codeRequests > 0) {
  const codeLimiter = limiter(15, codeRequests, 'Too many codes asked for. Try again in 15 minutes.');
  app.post(['/api/auth/code', '/api/auth/forgot'], codeLimiter);
}

app.use(express.json({ limit: '5mb' }));
// Record events (automations.js) learn who is signed in from the request.
app.use(withRequest);

app.get('/api/health', (req, res) => res.json({ ok: true }));
app.use('/uploads', filesRouter);
// The app restores its session with GET /me; the Account page's Edit profile
// and Change password use the other two. The rest of /api/auth is the
// sign-in screens' own routes/auth.js.
app.get('/api/auth/me', requireAuth, asyncHandler(currentUser));
app.patch('/api/auth/me', requireAuth, asyncHandler(updateProfile));
app.post('/api/auth/me/password', requireAuth, asyncHandler(changePassword));
app.use('/api/uploads', uploadsRouter);
// Routes of the plugins added in AppWand (plugins.g.js), before the pages'.
for (const plugin of plugins) plugin.mount?.(app);
app.use('/api', routes);

app.use((req, res) => res.status(404).json({ message: `No route for ${req.method} ${req.path}` }));
app.use(errorHandler);

// What a plugin reads before the first request (the roles' permissions).
for (const plugin of plugins) await plugin.ready?.();

const port = Number(process.env.PORT || 3000);
app.listen(port, () => console.log(`API listening on http://localhost:${port}/api`));
// The scheduled jobs and record events set up in AppWand (automations.g.js).
await startAutomations();
