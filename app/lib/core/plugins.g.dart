// Written by AppWand from the project's plugins: add or remove them in AppWand
// (Plugins), not here.
import 'package:flutter/widgets.dart';

import 'app_plugin.dart';
import '../plugins/access_control/access_control.dart' as access_control;
import '../plugins/record_ownership/record_ownership.dart' as record_ownership;
import '../plugins/app_notifications/app_notifications.dart' as app_notifications;
import '../plugins/app_search/app_search.dart' as app_search;

export 'app_plugin.dart';

/// The installed plugins with a Flutter part, in the order they were added.
const List<AppPlugin> appPlugins = [access_control.plugin, record_ownership.plugin, app_notifications.plugin, app_search.plugin];

/// Runs each plugin's start hook; main() awaits it before runApp.
Future<void> startPlugins() async {
  for (final plugin in appPlugins) {
    await plugin.start?.call();
  }
}

/// [child] wrapped by each plugin's wrap hook (MaterialApp.builder).
Widget wrapWithPlugins(Widget child) {
  var wrapped = child;
  for (final plugin in appPlugins) {
    wrapped = plugin.wrap?.call(wrapped) ?? wrapped;
  }
  return wrapped;
}
