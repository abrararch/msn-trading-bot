import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/background_engine_service.dart';
import 'services/signal_notification_service.dart';
import 'services/signal_service.dart';
import 'services/future_signal_forecast_service.dart';
import 'services/economic_news_service.dart';
import 'services/session_manager.dart';
import 'services/account_manager.dart';
import 'design_system/app_theme.dart';
import 'routing/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Silence the engine's diagnostic log in release builds.
  //
  // `debugPrint` is NOT stripped from release builds — every one of the ~90
  // per-tick and per-scan-cycle lines this app emits was doing a real platform
  // log write on the UI isolate in shipped APKs. Debug and profile builds keep
  // the full log, which is where it is actually read.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Fonts come from assets/google_fonts/, never from the network.
  //
  // Runtime fetching is what made the first launch flicker: text painted in a
  // fallback face, then reflowed once the download landed, and on a cold start
  // with no connection it never landed at all. Every weight the app asks for
  // is bundled (see pubspec.yaml), so turning fetching off removes the HTTP
  // round trip, the file-system cache check and the reflow.
  GoogleFonts.config.allowRuntimeFetching = false;

  // Notification channel + task options for the background collector. Cheap,
  // and a no-op on platforms where it is not supported.
  BackgroundEngineService.init();
  await BackgroundEngineService.loadPreference();

  // Separate, audible "a signal just locked" channel — distinct from the
  // background collector's silent status notification above. Must be
  // initialized once per isolate; see BackgroundEngineTaskHandler.onStart()
  // for the background-isolate counterpart.
  await SignalNotificationService.init();

  // CRITICAL: Initialize SessionManager FIRST so the secure token is loaded
  // from Android Keystore before SignalService attempts its first connection.
  await SessionManager.instance.initialize();

  // App-level account gate (Gmail + license key) — separate from the Quotex
  // broker session above. Must resolve before the splash screen decides
  // whether to route to /login, /license or /dashboard.
  await AccountManager.instance.initialize();

  // If a previous session handed the engine to the background service, take it
  // back before the UI's own SignalService opens a second socket.
  await BackgroundEngineService.stop();
  await BackgroundEngineService.waitForFlush();

  // Mark UI isolate as active so the foreground task runs in single-socket keepalive mode
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kUiIsolateActiveKey, true);
  } catch (_) {}

  final signalService = SignalService();
  // The ONLY future-signal pipeline. It owns no socket and no second data
  // source: every direction comes from SignalService's own engine, over candles
  // the app already has — it sends NOTHING to the broker. Scanning starts only
  // if the user previously switched it ON (persisted); loadPrefs() honours that.
  final forecastService = FutureSignalForecastService(signalService)
    ..loadPrefs();

  WidgetsBinding.instance
      .addObserver(_EngineHandoffObserver(signalService));

  // Built exactly once. See createAppRouter()'s doc comment — QuotexSignalApp
  // is rebuilt on every SignalService notification, and a router rebuilt with
  // it would reset the navigation stack on every broker tick.
  final router = createAppRouter();

  runApp(QuotexSignalApp(
    signalService: signalService,
    forecastService: forecastService,
    router: router,
  ));

  // Background collection now defaults to ON (see BackgroundEngineService),
  // so ask for the notification permission and the battery-optimisation
  // exemption right away instead of waiting for the user to find the
  // Settings toggle. Both calls are no-ops if already granted, so this is
  // safe to run on every cold start. Fired after runApp so the system
  // dialogs never delay the first frame.
  if (BackgroundEngineService.isEnabled) {
    unawaited(BackgroundEngineService.requestPermissions());
  }
  unawaited(SignalNotificationService.requestPermission());
}

/// Hands the engine between the UI isolate and the background service as the
/// app moves on and off screen.
///
/// Ensures exactly ONE broker socket exists at any moment (protecting against
/// account bans), while using the Android Foreground Service WakeLock & WifiLock
/// to keep the primary socket and T-3s lock timers firing with exact precision.
class _EngineHandoffObserver extends WidgetsBindingObserver {
  _EngineHandoffObserver(this.signalService);

  final SignalService signalService;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Send immediate keepalive ping when backgrounded
        signalService.sendPing();
        // Start Foreground Service keepalive so Android OS maintains WakeLock & WifiLock,
        // preventing the OS from sleeping CPU, killing timers, or dropping the primary broker socket.
        // Single-socket invariant is preserved because kUiIsolateActiveKey is true.
        if (BackgroundEngineService.isSupported &&
            BackgroundEngineService.isEnabled) {
          unawaited(BackgroundEngineService.start());
        }
        break;
      case AppLifecycleState.detached:
        // Last callback before this isolate goes away — hand over headlessly
        _onDetached();
        break;
      case AppLifecycleState.resumed:
        // Multitasking resume: verify socket is active and refresh status
        signalService.ensureConnected();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        signalService.sendPing();
        break;
    }
  }

  Future<void> _onDetached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kUiIsolateActiveKey, false);
    } catch (_) {}
    await signalService.suspendForHandoff();
  }
}

class QuotexSignalApp extends StatelessWidget {
  final SignalService signalService;
  final FutureSignalForecastService forecastService;
  final GoRouter router;

  const QuotexSignalApp({
    super.key,
    required this.signalService,
    required this.forecastService,
    required this.router,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SignalService>.value(value: signalService),
        ChangeNotifierProvider<FutureSignalForecastService>.value(
            value: forecastService),
        ChangeNotifierProvider<EconomicNewsService>.value(
            value: EconomicNewsService.instance),
      ],
      // Selector, not Consumer: this widget sits above the router, so
      // whatever it rebuilds cascades a rebuild through the ENTIRE active
      // screen (charts, lists, everything). isDarkMode is the only field it
      // reads, so it must only rebuild when that one value actually flips —
      // not on every SignalService.notifyListeners(), which fires on a
      // throttle as often as every 500ms for the lifetime of the app. A plain
      // Consumer here was forcing a full-tree rebuild twice a second on every
      // screen, including ones with no live data on them at all (Settings,
      // History, News).
      child: Selector<SignalService, bool>(
        selector: (context, service) => service.isDarkMode,
        builder: (context, isDarkMode, _) {
          return MaterialApp.router(
            title: 'MSN TERMINAL',
            debugShowCheckedModeBanner: false,
            themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            routerConfig: router,
          );
        },
      ),
    );
  }
}
