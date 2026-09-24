import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../design_system/app_colors.dart';
import '../routing/app_router.dart';
import '../services/account_manager.dart';

/// Second gate after login: the user must redeem a license key before
/// reaching the dashboard. Keys are minted by the operator (see
/// generate_license_keys.py) and handed out manually — one key, one use.
class LicenseKeyScreen extends StatefulWidget {
  const LicenseKeyScreen({super.key});

  @override
  State<LicenseKeyScreen> createState() => _LicenseKeyScreenState();
}

class _LicenseKeyScreenState extends State<LicenseKeyScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await AccountManager.instance.redeemLicenseKey(_controller.text);

    if (!mounted) return;
    setState(() => _loading = false);

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    HapticFeedback.mediumImpact();
    context.go(AppRoutes.dashboard);
  }

  Future<void> _signOut() async {
    await AccountManager.instance.signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final email = AccountManager.instance.email ?? '';

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.goldBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.goldBorder),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  size: 32,
                  color: AppColors.goldAccent,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'ACTIVATE YOUR LICENSE',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Signed in as $email\nEnter the license key you were given to unlock the app.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondaryDark,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                style: GoogleFonts.spaceMono(
                  color: Colors.white,
                  fontSize: 16,
                  letterSpacing: 2,
                ),
                decoration: InputDecoration(
                  hintText: 'XXXX-XXXX-XXXX-XXXX',
                  hintStyle: GoogleFonts.spaceMono(
                    color: AppColors.textMutedDark,
                    letterSpacing: 2,
                  ),
                  filled: true,
                  fillColor: AppColors.darkCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.darkBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.goldAccent),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _redeem,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.goldAccent,
                    foregroundColor: const Color(0xFF1F1500),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          'Activate',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.putRedBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.putRedBorder),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppColors.putRed,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextButton(
                onPressed: _loading ? null : _signOut,
                child: Text(
                  'Sign out',
                  style: GoogleFonts.inter(
                    color: AppColors.textMutedDark,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
