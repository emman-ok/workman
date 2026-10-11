// Owned by AppWand.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.g.dart';
import 'core/i18n.dart';
import 'core/intro.dart';
import 'core/plugins.g.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeModeController.load();
  await LanguageController.load();
  await IntroSeen.load();
  await startPlugins();
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: watchThemeMode(ref),
      // The app's languages are picked in AppWand ("Languages"); tr() gives
      // every text in the one in use.
      locale: watchLocale(ref),
      supportedLocales: appLocales,
      localizationsDelegates: appLocalizationsDelegates,
      routerConfig: ref.watch(routerProvider),
      // The plugins added in AppWand may cover every screen (a lock screen).
      builder: (context, child) => wrapWithPlugins(child ?? const SizedBox.shrink()),
    );
  }
}
