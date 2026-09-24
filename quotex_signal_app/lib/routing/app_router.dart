// ═════════════════════════════════════════════════════════════════════════════
// APP ROUTER — declarative, SaaS-style navigation
//
// Replaces the old scheme of one StatefulWidget (`MainShell`) holding an
// `_currentIndex` int and an `IndexedStack` it flipped by hand. That worked,
// but it meant the app had no real routes: no addressable location for "which
// screen am I on", no back-stack semantics for a screen pushed from another,
// and every "go to tab N" call site had to know a magic index.
//
// `StatefulShellRoute.indexedStack` is go_router's purpose-built answer to
// "bottom-nav app that must preserve each tab's state": each branch below gets
// its own Navigator and its own IndexedStack slot, so switching tabs is still
// instant and state-preserving — the only thing that changed is that it now
// has a real path.
//
// Five primary branches (Dashboard / Scanner / Lab / Future / More) instead of
// the old seven flat tabs. History, News and Settings moved under `/more` as
// pushed sub-routes of that branch: the bottom nav stays visible while
// browsing them (same Scaffold, same shell), and a real back arrow replaces
// what used to be a hamburger icon with nowhere to go back to.
// ═════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/app_shell.dart';
import '../screens/auto_scan_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/future_signals_screen.dart';
import '../screens/manual_signal_screen.dart';
import '../screens/more_screen.dart';
import '../screens/news_calendar_screen.dart';
import '../screens/results_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/candle_storage_details_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/license_key_screen.dart';

/// Every path in the app, named once so nothing else has to spell out a
/// literal string and risk a typo silently mismatching a route.
abstract final class AppRoutes {
  static const splash = '/splash';
  static const login = '/login';
  static const license = '/license';
  static const dashboard = '/dashboard';
  static const scanner = '/scanner';
  static const lab = '/lab';
  static const future = '/future';
  static const more = '/more';
  static const moreHistory = '/more/history';
  static const moreNews = '/more/news';
  static const moreSettings = '/more/settings';
  static const moreStorage = '/more/storage';
}

/// Routes a legacy flat tab index to its new path.
///
/// `DashboardScreen.onNavigateTab` and the top-bar news chip were both built
/// against the old scheme — Dashboard=0, Scanner=1, Lab=2, Future=3,
/// History=4, Settings=5, News=6, Storage=7 — and neither needed to change: this is the
/// one place that translates an old index into where it actually lives now.
/// Indices 0-3 switch tabs in place (`go`, preserving the other branches'
/// state); 4/5/6/7 are pushed on top of the More branch, since they are no
/// longer tabs of their own.
void navigateToLegacyTab(BuildContext context, int legacyIndex) {
  switch (legacyIndex) {
    case 0:
      context.go(AppRoutes.dashboard);
    case 1:
      context.go(AppRoutes.scanner);
    case 2:
      context.go(AppRoutes.lab);
    case 3:
      context.go(AppRoutes.future);
    // `go`, not `push`: pushing a nested branch sub-route from a different
    // branch's current location does not resolve in go_router — `go` is what
    // the package's own StatefulShellRoute example uses for this exact case,
    // and it still lands on a real stacked page (`/more` then `/more/history`
    // as two pages on that branch's own Navigator), so the back arrow still
    // pops to the More menu correctly.
    case 4:
      context.go(AppRoutes.moreHistory);
    case 5:
      context.go(AppRoutes.moreSettings);
    case 6:
      context.go(AppRoutes.moreNews);
    case 7:
      context.go(AppRoutes.moreStorage);
  }
}

/// Builds the router.
///
/// Call this exactly ONCE, in `main()`, and hand the result down — never
/// rebuild it inside `QuotexSignalApp.build()`. That widget is rebuilt on
/// every `SignalService` notification (i.e. on every broker tick), and a
/// GoRouter constructed fresh each time would reset the entire navigation
/// stack — including whatever screen the user is currently looking at —
/// several times a second.
GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.license,
        builder: (context, state) => const LicenseKeyScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => DashboardScreen(
                  onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                  onNavigateTab: (i) => navigateToLegacyTab(context, i),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.scanner,
                builder: (context, state) => AutoScanScreen(
                  onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.lab,
                builder: (context, state) => ManualSignalScreen(
                  onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.future,
                builder: (context, state) => FutureSignalsScreen(
                  onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.more,
                builder: (context, state) => MoreScreen(
                  onOpenDrawer: () => Scaffold.of(context).openDrawer(),
                ),
                routes: [
                  GoRoute(
                    path: 'history',
                    builder: (context, state) =>
                        const ResultsScreen(showBackButton: true),
                  ),
                  GoRoute(
                    path: 'news',
                    builder: (context, state) =>
                        const NewsCalendarScreen(showBackButton: true),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) =>
                        const SettingsScreen(showBackButton: true),
                  ),
                  GoRoute(
                    path: 'storage',
                    builder: (context, state) =>
                        const CandleStorageDetailsScreen(showBackButton: true),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
