// The app's sentences in each language, for tests. The older screen tests
// check Portuguese text, so they pin the app to Portuguese with these.
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subshaul/l10n/l10n.dart';

export 'package:subshaul/l10n/l10n.dart';

final pt = lookupAppLocalizations(const Locale('pt'));
final en = lookupAppLocalizations(const Locale('en'));

/// For a MaterialApp built by a test: the app's own delegates.
const l10nDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const ptLocale = Locale('pt');

/// The whole app (SubshaulApp) follows the phone: these set the phone's
/// language for one test.
void phoneLanguage(WidgetTester tester, List<Locale> locales) {
  tester.platformDispatcher.localesTestValue = locales;
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
}

void phoneInPortuguese(WidgetTester tester) => phoneLanguage(tester, const [Locale('pt', 'BR')]);
