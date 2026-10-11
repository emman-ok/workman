// Owned by AppWand. The app's languages: tr() gives a text in the language in
// use, and LanguageSetting lets a person pick theirs (kept on the device).
// The languages and the translations are in translations.g.dart, written by
// AppWand ("Languages").
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'icons.dart';
import 'translations.g.dart';

export 'translations.g.dart' show appLanguages;

String _language = appLanguages.keys.first;

/// The code of the language in use: 'en', 'fr', 'pt-BR'.
String get currentLanguage => _language;

/// [text] in the language in use. Every text people read goes through it,
/// written in English: tr('Save'), tr('Delete {name}?', {'name': name}).
/// Each {key} is replaced by its value in [args]. A text with no translation
/// yet is shown as written.
String tr(String text, [Map<String, Object?> args = const {}]) {
  var out = appTranslations[_language]?[text] ?? text;
  for (final entry in args.entries) {
    out = out.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return out;
}

Locale _localeOf(String code) {
  final parts = code.split('-');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

/// The app's languages as locales, for MaterialApp.supportedLocales.
List<Locale> get appLocales => [for (final code in appLanguages.keys) _localeOf(code)];

/// The app's language that suits [locale] (the device's), or null.
String? _match(Locale locale) {
  final tag = locale.countryCode == null ? locale.languageCode : '${locale.languageCode}-${locale.countryCode}';
  if (appLanguages.containsKey(tag)) return tag;
  if (appLanguages.containsKey(locale.languageCode)) return locale.languageCode;
  // A regional form of the device's language: 'pt-BR' for Portuguese.
  for (final code in appLanguages.keys) {
    if (code.split('-').first == locale.languageCode) return code;
  }
  return null;
}

/// The language to use: the person's [picked] one, else the app's default
/// (set in AppWand), else the device's when the app has it, else the first.
String _resolve(String? picked) {
  if (picked != null && appLanguages.containsKey(picked)) return picked;
  if (appLanguages.containsKey(appDefaultLanguage)) return appDefaultLanguage;
  for (final locale in WidgetsBinding.instance.platformDispatcher.locales) {
    final match = _match(locale);
    if (match != null) return match;
  }
  return appLanguages.keys.first;
}

void _use(String code) {
  _language = code;
  // Dates and numbers (core/format.dart) follow the language when intl knows it.
  final tag = code.replaceAll('-', '_');
  final short = code.split('-').first;
  bool known(String locale) => DateFormat.localeExists(locale) && NumberFormat.localeExists(locale);
  Intl.defaultLocale = known(tag) ? tag : (known(short) ? short : null);
}

/// The locale in use, for MaterialApp.locale. Worked out in build, so new
/// languages or a new default from AppWand show on hot reload.
Locale watchLocale(WidgetRef ref) {
  _use(_resolve(ref.watch(languageChoiceProvider)));
  return _localeOf(_language);
}

/// The person's own choice; null until they pick one.
final languageChoiceProvider = NotifierProvider<LanguageController, String?>(LanguageController.new);

class LanguageController extends Notifier<String?> {
  static const String _key = 'language';
  static String? _saved;

  /// Reads the saved choice; main() awaits it before runApp.
  static Future<void> load() async {
    await initializeDateFormatting();
    final prefs = await SharedPreferences.getInstance();
    _saved = prefs.getString(_key);
    _use(_resolve(_saved));
  }

  @override
  String? build() => _saved;

  Future<void> set(String code) async {
    if (!appLanguages.containsKey(code)) return;
    state = code;
    _saved = code;
    _use(code);
    _rebuildEverything();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }

  /// tr() is a plain function, so nothing rebuilds by itself when the
  /// language changes: every widget on screen is asked to, keeping its state.
  static void _rebuildEverything() {
    void visit(Element element) {
      element.markNeedsBuild();
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }
}

/// For MaterialApp.localizationsDelegates: Flutter's own texts (date pickers,
/// tooltips, the text direction) in the app's languages, and in English for
/// a language Flutter has no texts for.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  _EnglishMaterial(),
  _EnglishCupertino(),
];

class _EnglishMaterial extends LocalizationsDelegate<MaterialLocalizations> {
  const _EnglishMaterial();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) => DefaultMaterialLocalizations.load(locale);

  @override
  bool shouldReload(_EnglishMaterial old) => false;
}

class _EnglishCupertino extends LocalizationsDelegate<CupertinoLocalizations> {
  const _EnglishCupertino();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) => DefaultCupertinoLocalizations.load(locale);

  @override
  bool shouldReload(_EnglishCupertino old) => false;
}

/// The language setting: the app's languages by their own names, the choice
/// kept on the device. Nothing when the app has one language. The Account
/// page (/account) already shows it.
class LanguageSetting extends ConsumerWidget {
  const LanguageSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appLanguages.length < 2) return const SizedBox.shrink();
    ref.watch(languageChoiceProvider);
    return InputDecorator(
      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentLanguage,
          isExpanded: true,
          items: [
            for (final language in appLanguages.entries) DropdownMenuItem(value: language.key, child: Text(language.value)),
          ],
          onChanged: (code) {
            if (code != null) ref.read(languageChoiceProvider.notifier).set(code);
          },
        ),
      ),
    );
  }
}

/// A button that opens the app's languages, for a screen shown before
/// sign-in. Nothing when the app has one language.
class LanguageButton extends ConsumerWidget {
  const LanguageButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appLanguages.length < 2) return const SizedBox.shrink();
    ref.watch(languageChoiceProvider);
    return PopupMenuButton<String>(
      tooltip: tr('Language'),
      icon: const Icon(AppIcons.globe),
      initialValue: currentLanguage,
      onSelected: (code) => ref.read(languageChoiceProvider.notifier).set(code),
      itemBuilder: (context) => [
        for (final language in appLanguages.entries) PopupMenuItem<String>(value: language.key, child: Text(language.value)),
      ],
    );
  }
}
