// Access rules kept in the database. Owned by AppWand.
//
// Without the Roles & permissions plugin nothing registers here, and the page
// plan's roles (access.g.js) decide who may use a page. With it, the plugin
// registers itself: routes/index.js asks it on every request, and the account
// the app receives (auth/accounts.js, publicUser) carries the permissions of
// its role, which the app reads with AuthState.can('<page id>.<action>').
let access = null;
const routers = new Map();

/** The plugin: { check(id, req, res, next), permissionsOf(role) }. */
export function setAccess(value) {
  access = value;
}

/** The registered access rules, or null when the page plan's roles apply. */
export const getAccess = () => access;

/** routes/index.js: a page behind sign-in, with its router (the plugin reads which actions it has). */
export function notePage(id, pageRouter) {
  routers.set(id, pageRouter);
}

/** Every page behind sign-in: id → express Router. */
export const pageRouters = () => routers;

/** The permissions of [role] for the app, or undefined without the plugin. */
export const permissionsOf = (role) => access?.permissionsOf(role);

/** The name [role] was given in the app, or undefined without the plugin. */
export const roleNameOf = (role) => access?.roleNameOf?.(role);
