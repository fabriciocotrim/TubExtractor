import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'l10n/l10n.dart';
import 'screens/home_screen.dart';
import 'share_intake.dart';
import 'widgets/crystal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = await AppState.create();
  runApp(SubshaulApp(app: app, intake: ShareIntake()));
}

class SubshaulApp extends StatefulWidget {
  const SubshaulApp({super.key, required this.app, required this.intake});
  final AppState app;
  final ShareIntake intake;

  static final _light = crystalTheme(Brightness.light);
  static final _dark = crystalTheme(Brightness.dark);

  @override
  State<SubshaulApp> createState() => _SubshaulAppState();
}

class _SubshaulAppState extends State<SubshaulApp> {
  late ThemeMode _mode = widget.app.themeMode;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_onApp);
  }

  @override
  void didUpdateWidget(SubshaulApp old) {
    super.didUpdateWidget(old);
    if (identical(old.app, widget.app)) return;
    old.app.removeListener(_onApp);
    widget.app.addListener(_onApp);
    _mode = widget.app.themeMode;
  }

  @override
  void dispose() {
    widget.app.removeListener(_onApp);
    super.dispose();
  }

  // The app notifies on every job progress step; only a theme change
  // rebuilds the MaterialApp.
  void _onApp() {
    if (widget.app.themeMode != _mode) {
      setState(() => _mode = widget.app.themeMode);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TubExtractor',
    debugShowCheckedModeBanner: false,
    // English and Portuguese, following the phone (D-27, D-28). A language
    // change with the app open only redraws the text: the manifest handles
    // "locale" itself, so no job stops.
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: appLocales,
    localeListResolutionCallback: (phone, _) => resolveAppLocale(phone),
    theme: SubshaulApp._light,
    darkTheme: SubshaulApp._dark,
    themeMode: _mode,
    // Theme button: colors blend over half a second instead of jumping.
    // The MediaQuery here comes from the View, so the system "remove
    // animations" setting turns the blend off.
    themeAnimationDuration: MediaQuery.maybeDisableAnimationsOf(context) == true
        ? Duration.zero
        : const Duration(milliseconds: 500),
    themeAnimationCurve: const Cubic(0.22, 1, 0.36, 1),
    home: HomeScreen(app: widget.app, intake: widget.intake),
  );
}
