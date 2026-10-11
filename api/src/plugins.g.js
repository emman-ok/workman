// Written by AppWand from the project's plugins: add or remove them in AppWand
// (Plugins), not here. Each one default-exports { id, storage?, mount?, ready? }.
import accessControl from './plugins/access-control/index.js';
import recordOwnership from './plugins/record-ownership/index.js';
import appNotifications from './plugins/app-notifications/index.js';
import appSearch from './plugins/app-search/index.js';

/** The installed plugins with an API part, in the order they were added. server.js calls each one's mount(app), then awaits its ready(). */
export const plugins = [accessControl, recordOwnership, appNotifications, appSearch];

/** Where uploaded files go: a plugin's { save, link }, or null for the uploads/ folder. */
export const storage = plugins.find((plugin) => plugin.storage)?.storage ?? null;
