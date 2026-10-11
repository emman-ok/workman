// What a plugin added in AppWand can hook into. Owned by AppWand; the list of
// plugins is core/plugins.g.dart.
import 'package:flutter/widgets.dart';

import 'api_client.dart' show ApiLayer;
import 'auth/auth_controller.dart' show AuthState;

export 'api_client.dart' show ApiCall, ApiClient, ApiException, ApiLayer;

/// A file chosen to upload: its bytes and its name.
typedef PickedUpload = ({List<int> bytes, String name});

/// A page a plugin adds to the app: a route inside the app's navigation and
/// an entry at the end of the menu, for those whose role has [permission]
/// and is one of [roles].
class PluginPage {
  const PluginPage({
    required this.title,
    required this.route,
    required this.icon,
    required this.builder,
    this.permission,
    this.roles = const [],
    this.footer = false,
    this.group = '',
  });

  /// In English; shown through tr().
  final String title;
  final String route;
  final IconData icon;

  /// What AuthState.can must allow to see and open it; null for everyone signed in.
  final String? permission;

  /// The roles that see and open it; empty for everyone signed in.
  final List<String> roles;

  /// Kept out of the menu: an icon button at the foot of the side menu
  /// instead (in the account menu where the layout shows no side menu).
  final bool footer;

  /// The menu group it is listed under ("Settings"), in English and shown
  /// through tr(): after the app's own pages of that group, or as a group of
  /// its own at the end of the menu. Empty for the end of the menu, no label.
  final String group;
  final Widget Function(Map<String, String> params) builder;

  /// Whether [auth]'s account may see and open it.
  bool allows(AuthState auth) => (permission == null || auth.can(permission!)) && auth.hasRole(roles);
}

class AppPlugin {
  const AppPlugin({
    required this.id,
    this.start,
    this.wrap,
    this.accountSection,
    this.signInButtons,
    this.apiLayer,
    this.pickUpload,
    this.headerAction,
    this.pages = const [],
  });

  final String id;

  /// Pages of its own, in the menu after the app's (router.g.dart mounts them).
  final List<PluginPage> pages;

  /// Run in main() before runApp, e.g. to read a setting kept on the device.
  final Future<void> Function()? start;

  /// Wraps every screen (MaterialApp.builder), e.g. a lock screen on top.
  final Widget Function(Widget child)? wrap;

  /// A section of the Account page (PluginSettings): a heading and an
  /// AppSurface, with 24px above it.
  final WidgetBuilder? accountSection;

  /// Buttons under the sign-in and create-account forms (PluginSignInButtons),
  /// e.g. "Continue with Google", with their own spacing above.
  final WidgetBuilder? signInButtons;

  /// Sits between ApiClient and the network (the offline cache).
  final ApiLayer? apiLayer;

  /// Chooses the file FileField and pickAndUpload upload, in place of the
  /// system file picker (the camera, image compression). Null when cancelled.
  final Future<PickedUpload?> Function(BuildContext context, {required bool imagesOnly})? pickUpload;

  /// Something in the app's header, before the account menu, on every page
  /// while someone is signed in (the search box). [compact]: only an icon,
  /// where the header has no room (the grid layout's greeting); [color] is
  /// that header's text colour, null for the app bar's own.
  final Widget Function(BuildContext context, {required bool compact, Color? color})? headerAction;
}
