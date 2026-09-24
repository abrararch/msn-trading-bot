import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../design_system/app_colors.dart';
import '../design_system/app_typography.dart';
import '../design_system/app_components.dart';
import '../routing/app_router.dart';
import '../services/account_manager.dart';
import '../services/background_engine_service.dart';
import '../services/shadow_learning_engine.dart';
import '../services/signal_notification_service.dart';
import '../services/signal_service.dart';
import '../services/session_manager.dart';
import 'quotex_webview_login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onOpenDrawer;
  /// True when this screen was PUSHED (from the More menu) rather
  /// than shown as one of the shell's own tabs. Swaps the leading
  /// hamburger for a real back arrow — there is no drawer to open
  /// from here, only a route to pop.
  final bool showBackButton;
  const SettingsScreen({super.key, this.onOpenDrawer, this.showBackButton = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _backgroundEnabled = BackgroundEngineService.isEnabled;
  bool? _ignoringBatteryOpt;

  late TextEditingController _tokenController;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryOptStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The system battery-optimisation screen is a separate Activity — this
    // is how we notice the user came back from it without a plugin callback.
    if (state == AppLifecycleState.resumed) _refreshBatteryOptStatus();
  }

  Future<void> _refreshBatteryOptStatus() async {
    if (!BackgroundEngineService.isSupported) return;
    final ignoring = await BackgroundEngineService.isIgnoringBatteryOptimizations;
    if (mounted) setState(() => _ignoringBatteryOpt = ignoring);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenController.dispose();
    super.dispose();
  }

  void _saveToken(SignalService service) {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;
    service.updateToken(token);
    _tokenController.clear();
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session token saved securely in Keystore — connecting...')),
    );
  }

  void _clearSession(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Clear Quotex Session?', style: AppTypography.headingMedium()),
        content: Text(
          'This will remove your session credential from secure storage and disconnect the broker stream.',
          style: AppTypography.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTypography.caption()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.putRed, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              SessionManager.instance.clearToken();
            },
            child: const Text('Clear Session'),
          ),
        ],
      ),
    );
  }

  void _signOutOfApp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Sign Out?', style: AppTypography.headingMedium()),
        content: Text(
          'You will need to sign in with Google and re-enter your license key to use the app again.',
          style: AppTypography.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTypography.caption()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.putRed, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await AccountManager.instance.signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SignalService>();
    final isDark = service.isDarkMode;
    final session = SessionManager.instance;
    final account = AccountManager.instance;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      // top: false — this screen is hosted inside AppShell, whose
      // persistent header bar already reserves the real top safe-area
      // inset. A second SafeArea claiming it again was adding a dead
      // ~24-30px gap above every tab's own header.
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ─── 1. HEADER ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    if (widget.showBackButton) ...[
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : AppColors.lightCardElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : AppColors.textPrimaryLight, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ] else if (widget.onOpenDrawer != null) ...[
                      GestureDetector(
                        onTap: widget.onOpenDrawer,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : AppColors.lightCardElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          ),
                          child: Icon(Icons.menu_rounded, color: isDark ? Colors.white : AppColors.textPrimaryLight, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(alpha: 0.15),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: const Icon(Icons.settings_rounded, color: AppColors.primaryLight, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SETTINGS & SECURITY', style: AppTypography.headingMedium(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight)),
                          Text('Broker Session & Quantitative Terminal Config', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── 1.5 APP ACCOUNT CARD (Gmail + License) ────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TerminalCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_circle_rounded, color: AppColors.goldAccent, size: 18),
                          const SizedBox(width: 8),
                          Text('APP ACCOUNT', style: AppTypography.caption(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: account.isLicensed ? AppColors.callGreenBg : AppColors.putRedBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: account.isLicensed ? AppColors.callGreenBorder : AppColors.putRedBorder),
                            ),
                            child: Text(
                              account.isLicensed ? 'LICENSED' : 'UNLICENSED',
                              style: AppTypography.micro(
                                color: account.isLicensed ? AppColors.callGreen : AppColors.putRed,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Text(
                        account.email ?? 'Not signed in',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: AppTypography.monoBody(color: isDark ? Colors.white : AppColors.textPrimaryLight),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.putRed,
                            side: const BorderSide(color: AppColors.putRedBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _signOutOfApp(context),
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: Text('SIGN OUT', style: AppTypography.caption(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── 2. BROKER CONNECTION & SECURITY CARD ──────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TerminalCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.security_rounded, color: AppColors.primaryLight, size: 18),
                          const SizedBox(width: 8),
                          Text('BROKER CONNECTION & SESSION', style: AppTypography.caption(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          DataStatusBadge(status: session.authStatus, compact: true),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Session Fingerprint
                      Row(
                        children: [
                          // Flexible: the fingerprint is a long token-like
                          // string with nothing else in the row that can give
                          // way, so on a narrow phone it overflowed instead of
                          // truncating.
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('SESSION FINGERPRINT', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                                const SizedBox(height: 2),
                                Text(
                                  session.isConfigured ? session.tokenFingerprint() : 'No active session credential',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: AppTypography.monoBody(
                                    color: session.isConfigured ? AppColors.cyanTabular : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (session.isConfigured)
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.putRed, size: 20),
                              tooltip: 'Clear Session',
                              onPressed: () => _clearSession(context),
                            ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Browser Login Button
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.callGreen,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const QuotexWebviewLoginScreen()),
                            );
                          },
                          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                          label: Text('OPEN BUILT-IN QUOTEX BROWSER', style: AppTypography.caption(fontWeight: FontWeight.w900)),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Manual write-only paste field
                      Text('OR PASTE SESSION TOKEN MANUALLY', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _tokenController,
                              obscureText: true,
                              style: AppTypography.monoBody(),
                              decoration: InputDecoration(
                                hintText: 'Paste raw session token...',
                                filled: true,
                                fillColor: isDark ? AppColors.darkSurface : AppColors.lightCardElevated,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _saveToken(service),
                            child: const Text('SAVE'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── 3. QUANTITATIVE ENGINE PARAMETERS ─────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TerminalCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune_rounded, color: AppColors.amberWarning, size: 18),
                          const SizedBox(width: 8),
                          Text('SIGNAL ENGINE CONFIGURATION', style: AppTypography.caption(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('MTG Suggestions', style: AppTypography.subheading()),
                        subtitle: Text(
                          service.enableMtgSuggestions
                              ? 'ON — Post-loss MTG risk analysis cards will be shown'
                              : 'OFF — MTG-1 auto-calculated silently with signal result',
                          style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                        ),
                        value: service.enableMtgSuggestions,
                        activeThumbColor: AppColors.primary,
                        onChanged: (val) => service.setEnableMtgSuggestions(val),
                      ),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Symmetric Direction Balancing', style: AppTypography.subheading()),
                        subtitle: Text('Equal probability thresholding for CALL & PUT setups', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                        value: true,
                        activeThumbColor: AppColors.callGreen,
                        onChanged: (val) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── 3a. NOTIFICATION SOUNDS ────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TerminalCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.music_note_rounded, color: AppColors.cyanTabular, size: 18),
                          const SizedBox(width: 8),
                          Text('NOTIFICATION SOUNDS', style: AppTypography.caption(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pick any sound from your phone — including downloaded files. '
                        'Once picked, it\'s copied into the app, so deleting the '
                        'original file later won\'t remove it here.',
                        style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 4),

                      _SoundPickerRow(
                        type: SignalSoundType.generated,
                        title: 'Signal Detected',
                        icon: Icons.radar_rounded,
                        color: AppColors.amberWarning,
                        isDark: isDark,
                      ),
                      _SoundPickerRow(
                        type: SignalSoundType.locked,
                        title: 'Signal Locked',
                        icon: Icons.lock_clock_rounded,
                        color: AppColors.primaryLight,
                        isDark: isDark,
                      ),
                      _SoundPickerRow(
                        type: SignalSoundType.win,
                        title: 'Signal WON',
                        icon: Icons.check_circle_rounded,
                        color: AppColors.callGreen,
                        isDark: isDark,
                      ),
                      _SoundPickerRow(
                        type: SignalSoundType.loss,
                        title: 'Signal LOST',
                        icon: Icons.cancel_rounded,
                        color: AppColors.putRed,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── 3b. BACKGROUND COLLECTION & SHADOW LEARNER ────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TerminalCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hub_rounded,
                              color: AppColors.cyanTabular, size: 18),
                          const SizedBox(width: 8),
                          Text('BACKGROUND & LEARNING',
                              style:
                                  AppTypography.caption(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      if (BackgroundEngineService.isSupported)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Keep collecting off screen',
                              style: AppTypography.subheading()),
                          subtitle: Text(
                            _backgroundEnabled
                                ? 'ON — signals keep generating and settling with '
                                    'the app closed. A permanent notification is '
                                    'required by Android. No trade alerts are sent.'
                                : 'OFF — the engine stops when the app leaves the '
                                    'screen.',
                            style: AppTypography.micro(
                                color: isDark
                                    ? AppColors.textMutedDark
                                    : AppColors.textMutedLight),
                          ),
                          value: _backgroundEnabled,
                          activeThumbColor: AppColors.cyanTabular,
                          onChanged: (val) async {
                            if (val) await BackgroundEngineService.requestPermissions();
                            await BackgroundEngineService.setEnabled(val);
                            if (mounted) setState(() => _backgroundEnabled = val);
                          },
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Background collection is Android only. iOS destroys '
                            'the task the moment the app is force-closed and gives '
                            'background code roughly 30 seconds every 15 minutes, '
                            'which a live broker socket cannot survive.',
                            style: AppTypography.micro(
                                color: isDark
                                    ? AppColors.textMutedDark
                                    : AppColors.textMutedLight),
                          ),
                        ),

                      if (BackgroundEngineService.isSupported) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              _ignoringBatteryOpt == true
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              size: 15,
                              color: _ignoringBatteryOpt == true
                                  ? AppColors.callGreen
                                  : AppColors.putRed,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _ignoringBatteryOpt == true
                                    ? 'Battery optimisation: OFF for this app — Android will not throttle the connection.'
                                    : _ignoringBatteryOpt == false
                                        ? 'Battery optimisation: ON — Android can suspend the socket once the screen is off for a while.'
                                        : 'Checking battery optimisation status…',
                                style: AppTypography.micro(
                                    color: _ignoringBatteryOpt == true
                                        ? AppColors.callGreen
                                        : AppColors.putRed),
                              ),
                            ),
                          ],
                        ),
                        if (_ignoringBatteryOpt == false) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.putRed,
                                side: const BorderSide(color: AppColors.putRed),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => BackgroundEngineService
                                  .openBatteryOptimizationSettings(),
                              icon: const Icon(Icons.battery_saver_rounded, size: 16),
                              label: Text('DISABLE BATTERY OPTIMISATION',
                                  style: AppTypography.micro(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'On Xiaomi, Oppo, Vivo, Realme and Samsung devices you '
                          'must also enable Autostart for this app in the phone\'s '
                          'own Settings, or the system still kills it when you '
                          'swipe the app away.',
                          style: AppTypography.micro(
                              color: AppColors.amberWarning),
                        ),
                      ],

                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      Text('SHADOW LEARNER',
                          style: AppTypography.caption(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      _ShadowStatus(verdict: service.shadow.verdict, isDark: isDark),
                    ],
                  ),
                ),
              ),
            ),

            // ─── 4. APPEARANCE & DISPLAY ───────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: TerminalCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.palette_rounded, color: AppColors.purpleOtc, size: 18),
                          const SizedBox(width: 8),
                          Text('APPEARANCE', style: AppTypography.caption(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Institutional Dark Theme', style: AppTypography.subheading()),
                        subtitle: Text('Obsidian dark terminal with high contrast indicators', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                        value: isDark,
                        activeThumbColor: AppColors.primary,
                        onChanged: (val) => service.setThemeMode(val),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── 5. EXECUTIVE BRANDING & SYSTEM SPEC ───────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: Column(
                  children: [
                    const MsnBrandLogo(
                      size: 70,
                      isCard: true,
                      showText: true,
                      showSubtext: true,
                    ),
                    const SizedBox(height: 14),
                    TerminalCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SYSTEM & SECURITY SPECIFICATION', style: AppTypography.micro(fontWeight: FontWeight.bold, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight)),
                          const SizedBox(height: 8),
                          Text('• App Version: 3.2.0 VIP Institutional Terminal', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                          Text('• Engine: MSN v3.2 + Doji · Exhaustion · Session Filters', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                          Text('• Encryption: Android Keystore Hardware AES-256', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                          Text('• Invariant: Single WebSocket Connection Guard Active', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                          Text('• Broker Ticker: Quotex Native Binary Protocol', style: AppTypography.micro(color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the Notification Sounds card — shows the current sound
/// (default or a picked file's name) and lets the user pick a new one or
/// reset to default. Owns its own tiny bit of state (`_busy`) so a slow file
/// copy disables its own buttons without needing the whole screen to rebuild.
class _SoundPickerRow extends StatefulWidget {
  final SignalSoundType type;
  final String title;
  final IconData icon;
  final Color color;
  final bool isDark;

  const _SoundPickerRow({
    required this.type,
    required this.title,
    required this.icon,
    required this.color,
    required this.isDark,
  });

  @override
  State<_SoundPickerRow> createState() => _SoundPickerRowState();
}

class _SoundPickerRowState extends State<_SoundPickerRow> {
  bool _busy = false;

  Future<void> _choose() async {
    setState(() => _busy = true);
    final picked = await SignalNotificationService.pickCustomSound(widget.type);
    if (!mounted) return;
    setState(() => _busy = false);
    if (picked != null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.title} sound set to "$picked"')),
      );
    }
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    await SignalNotificationService.resetToDefault(widget.type);
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.title} sound reset to default')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final hasCustom = SignalNotificationService.hasCustomSound(widget.type);
    final label = SignalNotificationService.customSoundLabel(widget.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: widget.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: AppTypography.subheading()),
                const SizedBox(height: 2),
                Text(
                  hasCustom ? (label ?? 'Custom sound') : 'Default',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTypography.micro(
                    color: hasCustom
                        ? widget.color
                        : (isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            if (hasCustom)
              IconButton(
                icon: const Icon(Icons.restore_rounded, size: 20),
                tooltip: 'Reset to default',
                onPressed: _reset,
              ),
            IconButton(
              icon: const Icon(Icons.folder_open_rounded, size: 20),
              tooltip: 'Choose sound',
              onPressed: _choose,
            ),
          ],
        ],
      ),
    );
  }
}

/// Plain-language readout of the learner's gate.
///
/// The point of showing this is that "no edge found" is a RESULT, not an error
/// — the number it reports is the honest one, and hiding it would be how a
/// 49.8% engine gets mistaken for a 100%-confidence one.
class _ShadowStatus extends StatelessWidget {
  const _ShadowStatus({required this.verdict, required this.isDark});

  final ShadowVerdict verdict;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (verdict.status) {
      ShadowGateStatus.collecting => (
          AppColors.cyanTabular,
          Icons.hourglass_bottom_rounded,
          'COLLECTING'
        ),
      ShadowGateStatus.noEdgeFound => (
          AppColors.amberWarning,
          Icons.remove_circle_outline_rounded,
          'NO EDGE FOUND'
        ),
      ShadowGateStatus.promoted => (
          AppColors.callGreen,
          Icons.verified_rounded,
          'ACTIVE'
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: AppTypography.micro(
                    color: color, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          verdict.reason,
          style: AppTypography.micro(
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight),
        ),
        const SizedBox(height: 6),
        Text(
          'The learner trains continuously on real settled outcomes but cannot '
          'change a live signal until it beats the payout break-even out of '
          'sample. It can only ever remove a signal, never add or flip one.',
          style: AppTypography.micro(
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight),
        ),
      ],
    );
  }
}
