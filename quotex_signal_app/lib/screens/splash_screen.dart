import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../design_system/app_colors.dart';
import '../design_system/msn_brand_logo.dart';
import '../routing/app_router.dart';
import '../services/account_manager.dart';

/// Professional Executive Splash Screen for MSN Signal Bot.
///
/// Displays a high-tech boot sequence (3.8s) featuring brand identity,
/// dynamic initialization stages, and developer attribution for
/// "Software Developer Abrar Ahmad".
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  Timer? _statusTimer;
  Timer? _completeTimer;

  bool _hasNavigated = false;
  int _currentStepIndex = 0;

  static const List<String> _initSteps = [
    'INITIALIZING NEURAL MATRIX...',
    'CALIBRATING HIGH-FREQUENCY OTC FILTERS...',
    'SYNCHRONIZING BROKER FEED & SIGNALS...',
    'MSN SIGNAL ENGINE ARMED & READY',
  ];

  @override
  void initState() {
    super.initState();

    // 3.8 seconds total splash duration
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..forward();

    // Rotate status messages every 950ms
    _statusTimer = Timer.periodic(const Duration(milliseconds: 950), (timer) {
      if (!mounted) return;
      if (_currentStepIndex < _initSteps.length - 1) {
        setState(() {
          _currentStepIndex++;
        });
      } else {
        timer.cancel();
      }
    });

    // Auto-advance to dashboard at 3.8s
    _completeTimer = Timer(const Duration(milliseconds: 3800), () {
      _navigateToDashboard();
    });
  }

  void _navigateToDashboard() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _statusTimer?.cancel();
    _completeTimer?.cancel();

    // Best-effort re-check with the account server (e.g. license revoked
    // since last launch). Never blocks navigation — cached state below
    // decides where we go so the app still opens offline.
    unawaited(AccountManager.instance.refreshStatus());

    final account = AccountManager.instance;
    if (!account.isSignedIn) {
      context.go(AppRoutes.login);
    } else if (!account.isLicensed) {
      context.go(AppRoutes.license);
    } else {
      context.go(AppRoutes.dashboard);
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _completeTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // ─── AMBIENT BACKGROUND GLOW ─────────────────────────────────────
          Positioned(
            top: size.height * 0.18,
            left: size.width * 0.5 - 140,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.18),
                    AppColors.goldAccent.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ─── TOP BAR: SKIP BUTTON ────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 16),
                child: TextButton.icon(
                  onPressed: _navigateToDashboard,
                  icon: const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.goldLight,
                  ),
                  label: Text(
                    'SKIP',
                    style: GoogleFonts.spaceMono(
                      color: AppColors.goldLight,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    backgroundColor: const Color(0xFF131A29).withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: AppColors.goldAccent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 600.ms),
              ),
            ),
          ),

          // ─── CENTER CONTENT: BRAND & STATUS ──────────────────────────────
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),

                    // MSN Vector Brand Mark
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF090D16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.goldAccent.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                          BoxShadow(
                            color: AppColors.goldAccent.withValues(alpha: 0.12),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const MsnBrandLogo(
                        size: 84,
                        isCard: false,
                        showText: false,
                        showSubtext: false,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 700.ms, curve: Curves.easeOut)
                        .scale(
                          begin: const Offset(0.85, 0.85),
                          end: const Offset(1.0, 1.0),
                          duration: 700.ms,
                          curve: Curves.easeOutBack,
                        )
                        .shimmer(
                          duration: 1800.ms,
                          delay: 1000.ms,
                          color: AppColors.goldAccent.withValues(alpha: 0.3),
                        ),

                    const SizedBox(height: 24),

                    // Main Bot Title
                    Text(
                      'MSN SIGNAL BOT',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.5,
                        height: 1.1,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 250.ms)
                        .slideY(begin: 0.2, end: 0, duration: 600.ms),

                    const SizedBox(height: 8),

                    // Subtitle / Algorithm Tag
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.goldAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'EXECUTIVE QUANTITATIVE TERMINAL',
                          style: GoogleFonts.spaceMono(
                            color: AppColors.goldAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.goldAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 400.ms),

                    const SizedBox(height: 38),

                    // Animated Progress Bar
                    SizedBox(
                      width: 240,
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, _) {
                          return Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  height: 4,
                                  color: const Color(0xFF161F32),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: _progressController.value,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              AppColors.primary,
                                              AppColors.goldAccent,
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Live System Ticker Step
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.2),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: Text(
                                  _initSteps[_currentStepIndex],
                                  key: ValueKey<int>(_currentStepIndex),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.spaceMono(
                                    color: AppColors.textSecondaryDark,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 500.ms),

                    const Spacer(flex: 4),

                    // ─── DEVELOPER ATTRIBUTION BADGE ─────────────────────────
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 380),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C111C).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.goldAccent.withValues(alpha: 0.28),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: AppColors.goldAccent.withValues(alpha: 0.05),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Role Chip
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.goldBg,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.goldAccent.withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.terminal_rounded,
                                  size: 13,
                                  color: AppColors.goldAccent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'LEAD ARCHITECT & ENGINEER',
                                style: GoogleFonts.spaceMono(
                                  color: AppColors.goldLight,
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Developer Name (Highlighted prominently)
                          Text(
                            'Software Developer Abrar Ahmad',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Quantitative Specialization
                          Text(
                            'HIGH-FREQUENCY QUANTITATIVE SYSTEMS',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.spaceMono(
                              color: AppColors.textMutedDark,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 700.ms)
                        .slideY(begin: 0.3, end: 0, duration: 800.ms, curve: Curves.easeOutCubic),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
