// The request being answered, for code that runs deep inside it: a record
// event (automations.js) and the audit log plugin learn who is signed in from
// it. Owned by AppWand.
import { AsyncLocalStorage } from 'node:async_hooks';

const requests = new AsyncLocalStorage();

/** Middleware (server.js; again after multer, which loses it). */
export const withRequest = (req, res, next) => requests.run(req, next);

/** The request in progress; null outside one (a scheduled job, a script). */
export const currentRequest = () => requests.getStore() ?? null;
