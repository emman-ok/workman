// Record ownership: the records of the tables ticked in AppWand belong to a
// person, and the API only gives people their own
// (api/src/plugins/record-ownership). The app has nothing to enforce: this
// only tells a page whether to show whose a record is. Owned by AppWand
// (Plugins).
import '../../core/app_plugin.dart';
import '../../core/auth/auth_controller.dart';
import 'settings.g.dart';

const AppPlugin plugin = AppPlugin(id: 'record-ownership');

/// Whether the signed-in account reaches everyone's records of [table] on
/// the page with id [page], not only its own: show an owner column, an owner
/// filter or an owner picker only then.
///   seesEveryone(ref.watch(authProvider), 'orders', 'orders')
/// With the Roles & permissions plugin it is the page's "All records"
/// permission; without it, the roles ticked for the table in AppWand.
bool seesEveryone(AuthState auth, String page, String table) {
  final permissions = auth.permissions;
  if (permissions != null) return permissions.contains('$page.all');
  return ownershipRoles[table]?.contains(auth.role) ?? false;
}
