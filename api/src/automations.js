// Automations: scheduled jobs and record events. Owned by AppWand.
//
// Each file in ./automations/ default-exports its handlers. When it runs (the
// schedule, or the table and its events, and whether it is on) is set in
// AppWand and written to automations.g.js, never in the file itself.
//
//   a scheduled job    export default { async run({ now, log }) { ... } };
//   record events      export default { async beforeCreate(record, ctx) { ... }, async afterUpdate(record, ctx) { ... } };
//
// server.js calls startAutomations() once it listens. `node src/automations.js <id>`
// runs one scheduled job once and exits (Run now in AppWand). JOBS=off in .env
// keeps the schedules from starting (a second copy of the API); events stay on.
import 'dotenv/config';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { APP } from './app.g.js';
import { automations } from './automations.g.js';
import { modelForTable, sequelize } from './models/index.js';
import { currentRequest, withRequest } from './request.js';

const self =fileURLToPath(import.meta.url);
const dir = path.join(path.dirname(self), 'automations');

// Every automation's file is loaded here, on or off, so the check in AppWand
// finds one that fails to load. One planned but not written yet has no file.
const loaded = new Map();
for (const automation of automations) {
  const file = path.join(dir, `${automation.id}.js`);
  if (!fs.existsSync(file)) continue;
  try {
    const mod = await import(pathToFileURL(file).href);
    loaded.set(automation.id, mod.default ?? {});
  } catch (err) {
    console.error(`[automations] ${automation.id}.js failed to load`);
    throw err;
  }
}

// ── Who made the change ─────────────────────────────────────────────────────

/** Middleware (server.js): lets a record event know the signed-in account (ctx.user). */
export { withRequest };

const currentUser = () => currentRequest()?.user ?? null;

// ── Record events ───────────────────────────────────────────────────────────

/** The handler names, and the Sequelize hook each one is. */
const EVENTS = {
  beforeCreate: 'beforeCreate',
  afterCreate: 'afterCreate',
  beforeUpdate: 'beforeUpdate',
  afterUpdate: 'afterUpdate',
  beforeDelete: 'beforeDestroy',
  afterDelete: 'afterDestroy',
};

/** What an update changes, kept from before the save for the after handlers. */
const changes = new WeakMap();

/** After handlers still running, for a script that must not exit under them. */
const pending = new Set();

function noteChanges(record) {
  const changed = record.changed() || [];
  changes.set(record, { changed, previous: Object.fromEntries(changed.map((key) => [key, record.previous(key)])) });
}

function contextOf(event, record, options) {
  const change = event.endsWith('Update') ? changes.get(record) : null;
  return {
    event,
    changed: change?.changed ?? [],
    previous: change?.previous ?? {},
    user: currentUser(),
    // After handlers run once the change is committed, outside its transaction.
    transaction: event.startsWith('before') ? options?.transaction ?? null : null,
  };
}

function track(promise) {
  pending.add(promise);
  promise.finally(() => pending.delete(promise));
}

function wire(model, automation, handlers) {
  for (const [event, hook] of Object.entries(EVENTS)) {
    const handler = handlers[event];
    if (typeof handler !== 'function' || !automation.events.includes(event)) continue;
    const name = `appwand:${automation.id}:${event}`;
    if (event.startsWith('before')) {
      // Awaited: it may change the record, or refuse the change by throwing.
      model.addHook(hook, name, (record, options) => handler(record, contextOf(event, record, options)));
      continue;
    }
    // Never awaited and never failing the request: the change is already saved.
    model.addHook(hook, name, (record, options) => {
      const ctx = contextOf(event, record, options);
      const run = () =>
        track(
          Promise.resolve()
            .then(() => handler(record, ctx))
            .catch((err) => console.error(`[automations] ${automation.id} ${event} failed:`, err)),
        );
      const transaction = options?.transaction;
      if (transaction && typeof transaction.afterCommit === 'function') transaction.afterCommit(run);
      else run();
    });
  }
}

const wired = new Set();

/** Wires the event automations that are on to their tables' models. */
function wireEvents() {
  for (const automation of automations) {
    const handlers = loaded.get(automation.id);
    if (automation.type !== 'event' || !automation.enabled || !handlers) continue;
    const model = modelForTable(automation.table);
    if (!model) {
      console.warn(`[automations] ${automation.id}: the table ${automation.table} is not in the database.`);
      continue;
    }
    if (!wired.has(model)) {
      wired.add(model);
      // A change to many rows at once (Model.update, Model.destroy, bulkCreate,
      // an import) runs the handlers for each row.
      model.addHook('beforeBulkCreate', 'appwand:each', (records, options) => { options.individualHooks = true; });
      model.addHook('beforeBulkUpdate', 'appwand:each', (options) => { options.individualHooks = true; });
      model.addHook('beforeBulkDestroy', 'appwand:each', (options) => { options.individualHooks = true; });
      model.addHook('beforeUpdate', 'appwand:changes', (record) => noteChanges(record));
    }
    wire(model, automation, handlers);
  }
}

// ── Scheduled jobs ──────────────────────────────────────────────────────────

/** Runs the scheduled job [id] once. True when it finished without an error. */
export async function runAutomation(id) {
  const automation = automations.find((a) => a.id === id && a.type === 'schedule');
  const run = loaded.get(id)?.run;
  if (!automation || typeof run !== 'function') {
    console.error(`[automations] There is no scheduled job "${id}" with a run() to call.`);
    return false;
  }
  const started = Date.now();
  try {
    const result = await run({ now: new Date(), log: (...args) => console.log(`[${id}]`, ...args) });
    console.log(`[automations] ${id} finished in ${Date.now() - started} ms`, result ?? '');
    return true;
  } catch (err) {
    console.error(`[automations] ${id} failed:`, err);
    return false;
  }
}

let started = false;

/** Wires the record events and starts the schedules. server.js calls it once. */
export async function startAutomations() {
  if (started) return;
  started = true;
  wireEvents();
  const jobs = automations.filter((a) => a.type === 'schedule' && a.enabled && typeof loaded.get(a.id)?.run === 'function');
  if (jobs.length === 0 || process.env.JOBS === 'off') return;
  const { Cron } = await import('croner');
  for (const job of jobs) {
    try {
      // protect: a run that is still going when the next one is due makes that one wait its turn out.
      new Cron(job.cron, { timezone: APP.timezone || undefined, protect: true }, () => runAutomation(job.id));
    } catch (err) {
      console.error(`[automations] ${job.id} could not be scheduled (${job.cron}, ${APP.timezone}): ${err.message}`);
    }
  }
  console.log(`[automations] ${jobs.length} scheduled job${jobs.length === 1 ? '' : 's'} (${APP.timezone || 'server time'}): ${jobs.map((j) => j.id).join(', ')}`);
}

// `node src/automations.js <id>`: one run of a scheduled job, then exit.
if (process.argv[1] && path.resolve(process.argv[1]).toLowerCase() === self.toLowerCase()) {
  const id = process.argv[2];
  if (!id) {
    console.error('Usage: node src/automations.js <automation id>');
    process.exit(1);
  }
  wireEvents();
  const ok = await runAutomation(id);
  while (pending.size > 0) await Promise.allSettled([...pending]);
  await sequelize.close().catch(() => {});
  process.exit(ok ? 0 : 1);
}
