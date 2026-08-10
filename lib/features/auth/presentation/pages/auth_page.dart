import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/forgot_password_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../features/profile/data/username_service.dart';
import '../../../../core/responsive/breakpoints.dart';
import '../../../../shared/navigation/app_routes.dart';
import '../../../../shared/widgets/alsamos_logo.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../providers/auth_provider.dart';

/// Pixel-perfect port of web `AuthPage.tsx` (login / signup).
///
/// Matches:
/// - Animated radial glow background (3 blobs, primary alpha 0.10/0.05)
/// - Glass-strong auth card (24px radius, alpha 0.85, soft shadow)
/// - Mode toggle Sign In / Sign Up with active background pill
/// - Inputs with leading lucide icon (user/atSign/mail/lock)
/// - Eye/EyeOff toggle on password & confirm password
/// - Hero gradient submit button with ArrowRight icon
/// - Validation messages (Uzbek) shown via SnackBar (like sonner toast)
/// - Footer: Privacy • Terms • Help Center
class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage>
    with SingleTickerProviderStateMixin {
  bool _isSignUp = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _submitting = false;
  bool _readRouteExtra = false;

  void _togglePassword() {
    if (mounted) {
      setState(() {
        _showPassword = !_showPassword;
      });
    }
  }

  void _toggleConfirm() {
    if (mounted) {
      setState(() {
        _showConfirm = !_showConfirm;
      });
    }
  }

  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  late final AnimationController _entryCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scaleAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutBack);
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _fullName.dispose();
    _username.dispose();
    _identifier.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_readRouteExtra) return;
    _readRouteExtra = true;
    final extra = GoRouterState.of(context).extra;
    if (extra is Map && extra['identifier'] is String) {
      _identifier.text = (extra['identifier'] as String).trim();
      _isSignUp = false;
    }
  }

  void _resetForm() {
    _fullName.clear();
    _username.clear();
    _identifier.clear();
    _password.clear();
    _confirm.clear();
  }

  /// Zod-equivalent validation (web parity).
  String? _validate() {
    final id = _identifier.text.trim();
    final pw = _password.text;

    if (_isSignUp) {
      final name = _fullName.text.trim();
      final user = _username.text.trim();
      final conf = _confirm.text;

      if (name.length < 2) {
        return 'Ism kamida 2 ta belgidan iborat bo‘lsin';
      }
      if (name.length > 100) return 'Ism juda uzun';
      if (user.length < 3) {
        return 'Foydalanuvchi nomi kamida 3 ta belgidan iborat bo‘lsin';
      }
      if (user.length > 30) return 'Foydalanuvchi nomi juda uzun';
      if (!RegExp(r'^[a-z0-9_]+$').hasMatch(user)) {
        return 'Faqat kichik harflar, raqamlar va _ ishlating';
      }
      if (!_isValidEmail(id)) return 'Ro‘yxatdan o‘tish uchun email kiriting';
      if (id.length > 255) return 'Identifikator juda uzun';
      if (pw.length < 8) {
        return 'Parol kamida 8 ta belgidan iborat bo‘lsin';
      }
      if (pw.length > 128) return 'Parol juda uzun';
      if (pw != conf) return 'Parollar mos emas';
    } else {
      if (id.length < 3) {
        return 'Iltimos, email, foydalanuvchi nomi yoki telefon raqamini kiriting';
      }
      if (id.length > 255) return 'Identifikator juda uzun';
      if (pw.isEmpty) return 'Parolni kiriting';
      if (pw.length > 128) return 'Parol juda uzun';
    }
    return null;
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
        .hasMatch(value.trim().toLowerCase());
  }

  Future<void> _submit() async {
    if (_submitting) return;
    HapticFeedback.lightImpact();
    final err = _validate();
    if (err != null) {
      AppToast.error(context, err);
      return;
    }
    if (mounted) setState(() => _submitting = true);
    try {
      final notifier = ref.read(authProvider.notifier);
      if (_isSignUp) {
        final usernameService = UsernameService();
        final usernameResult = await usernameService.checkAvailability(
          _username.text.trim(),
        );
        if (!usernameResult.available) {
          AppToast.error(context,
              usernameResult.localizedMessage ?? 'Username band');
          setState(() => _submitting = false);
          return;
        }
        await notifier.signUp(
          _identifier.text.trim().toLowerCase(),
          _password.text,
          displayName: _fullName.text.trim(),
          username: _username.text.trim(),
        );
        if (!mounted) return;
        AppToast.success(context, 'Akkaunt yaratildi! Alsamosga xush kelibsiz.');
      } else {
        await notifier.signInWithPassword(
            _identifier.text.trim(), _password.text);
        if (!mounted) return;
        AppToast.success(context, 'Xush kelibsiz!');
      }
      if (mounted && ref.read(authProvider).isAuthenticated) {
        context.go(AppRoutes.home);
      }
    } on MfaRequiredException {
      if (!mounted) return;
      final ok = await _showMfaVerifyDialog();
      if (ok && mounted && ref.read(authProvider).isAuthenticated) {
        AppToast.success(context, '2FA tasdiqlandi. Xush kelibsiz!');
        context.go(AppRoutes.home);
      }
    } on AuthException catch (e) {
      AppToast.error(context, friendlyError(e));
    } on TimeoutException {
      AppToast.error(
        context,
        'Ulanish vaqti tugadi. Internetni tekshirib qayta urinib ko‘ring.',
      );
    } catch (e) {
      AppToast.error(
        context,
        'Xatolik yuz berdi. Qaytadan urinib ko‘ring.',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _showMfaVerifyDialog() async {
    final code = TextEditingController();
    String? error;
    var loading = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Ikki bosqichli tasdiqlash'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Authenticator ilovasidagi 6 xonali kodni kiriting.'),
              const SizedBox(height: 12),
              TextField(
                controller: code,
                autofocus: true,
                maxLength: 6,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  counterText: '',
                  errorText: error,
                  hintText: '000000',
                ),
                onSubmitted: (_) async {
                  if (loading) return;
                  setLocal(() {
                    loading = true;
                    error = null;
                  });
                  try {
                    await ref
                        .read(authProvider.notifier)
                        .verifyMfaCode(code.text);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    setLocal(() {
                      loading = false;
                      error = 'Kod noto‘g‘ri yoki eskirgan';
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      await ref.read(authProvider.notifier).logout();
                      if (ctx.mounted) Navigator.pop(ctx, false);
                    },
              child: const Text('Bekor'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      setLocal(() {
                        loading = true;
                        error = null;
                      });
                      try {
                        await ref
                            .read(authProvider.notifier)
                            .verifyMfaCode(code.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setLocal(() {
                          loading = false;
                          error = 'Kod noto‘g‘ri yoki eskirgan';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tasdiqlash'),
            ),
          ],
        ),
      ),
    );
    code.dispose();
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AlsamosColors.of(context);
    final primary = theme.colorScheme.primary;

    ref.listen(authProvider, (prev, next) {
      if (next.isAuthenticated) context.go(AppRoutes.home);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final responsive = Responsive.of(context);
        final horizontalPadding = responsive.isMobile ? 12.0 : 24.0;
        final verticalPadding = responsive.isMobile ? 12.0 : 24.0;
        final cardPadding = responsive.isMobile ? 20.0 : 32.0;
        final cardMaxWidth = responsive.isMobile ? 420.0 : 440.0;

        return Scaffold(
          backgroundColor: c.background,
          body: Stack(
            children: [
              // Animated-style background glows (3 blobs like web).
              Positioned(
                  top: -220,
                  left: -220,
                  child: _glow(primary.withValues(alpha: 0.10), 460)),
              Positioned(
                  bottom: -220,
                  right: -220,
                  child: _glow(primary.withValues(alpha: 0.10), 460)),
              Positioned(
                  top: 80,
                  right: 40,
                  child: _glow(primary.withValues(alpha: 0.05), 300)),
              Center(
                child: SafeArea(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                      vertical: verticalPadding,
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.92, end: 1)
                            .animate(_scaleAnim),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: cardMaxWidth,
                            minWidth: constraints.maxWidth < 360 ||
                                    responsive.isMobile
                                ? 0
                                : 360,
                          ),
                          child: Container(
                            padding: EdgeInsets.all(cardPadding),
                            decoration: BoxDecoration(
                              color: c.card.withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: c.border.withValues(alpha: 0.5),
                                  width: 1),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    blurRadius: 32,
                                    offset: const Offset(0, 12)),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AlsamosLogo(size: AlsamosLogoSize.xl),
                                const SizedBox(height: 16),
                                Text(
                                  'Ulaning, ulashing, kashf eting.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: c.mutedForeground,
                                      fontSize: 14,
                                      height: 1.4),
                                ),
                                const SizedBox(height: 28),
                                // Mode toggle
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                      color: c.muted,
                                      borderRadius: BorderRadius.circular(12)),
                                  child: Row(
                                    children: [
                                      _modeTab('Sign In', !_isSignUp, () {
                                        HapticFeedback.selectionClick();
                                        if (mounted) {
                                          setState(() => _isSignUp = false);
                                        }
                                        _resetForm();
                                      }, c),
                                      _modeTab('Sign Up', _isSignUp, () {
                                        HapticFeedback.selectionClick();
                                        if (mounted) {
                                          setState(() => _isSignUp = true);
                                        }
                                        _resetForm();
                                      }, c),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 22),
                                // Animated swap between login / signup forms
                                AbsorbPointer(
                                  absorbing: _submitting,
                                  child: AnimatedSize(
                                    duration: const Duration(milliseconds: 220),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedSwitcher(
                                      duration:
                                          const Duration(milliseconds: 240),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (child, anim) {
                                        final curved = CurvedAnimation(
                                          parent: anim,
                                          curve: Curves.easeOutCubic,
                                        );
                                        return FadeTransition(
                                          opacity: curved,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0, 0.035),
                                              end: Offset.zero,
                                            ).animate(curved),
                                            child: ScaleTransition(
                                              scale: Tween<double>(
                                                      begin: 0.985, end: 1)
                                                  .animate(curved),
                                              child: child,
                                            ),
                                          ),
                                        );
                                      },
                                      child: _isSignUp
                                          ? _signupFields(c)
                                          : _loginFields(c),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                // Hero submit button
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: AppColors.gradientPrimary,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                primary.withValues(alpha: 0.35),
                                            blurRadius: 18,
                                            offset: const Offset(0, 6)),
                                      ],
                                    ),
                                    child: TextButton(
                                      onPressed: _submitting ? null : _submit,
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            theme.colorScheme.onPrimary,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                      ),
                                      child: _submitting
                                          ? SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                  color: theme
                                                      .colorScheme.onPrimary))
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                    _isSignUp
                                                        ? 'Create Account'
                                                        : 'Sign In',
                                                    style: TextStyle(
                                                        color: theme.colorScheme
                                                            .onPrimary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 15)),
                                                const SizedBox(width: 6),
                                                Icon(LucideIcons.arrowRight,
                                                    size: 17,
                                                    color: theme
                                                        .colorScheme.onPrimary),
                                              ],
                                            ),
                                    ),
                                  ),
                                ),
                                if (!_isSignUp) ...[
                                  const SizedBox(height: 14),
                                  TextButton(
                                    onPressed: () => ForgotPasswordDialog.show(
                                      context,
                                      initialEmail:
                                          _identifier.text.trim().contains('@')
                                              ? _identifier.text.trim()
                                              : null,
                                    ),
                                    child: Text('Forgot Password?',
                                        style: TextStyle(
                                            color: primary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                  ),
                                ],
                                const SizedBox(height: 22),
                                Divider(color: c.border, height: 1),
                                const SizedBox(height: 18),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _footerLink('Privacy', c),
                                    _dot(c),
                                    _footerLink('Terms', c),
                                    _dot(c),
                                    _footerLink('Help Center', c),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _loginFields(AlsamosColors c) {
    return Column(
      key: const ValueKey('login'),
      children: [
        _field(
          _identifier,
          'Email, Username, or Phone Number',
          LucideIcons.mail,
          c,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [
            AutofillHints.username,
            AutofillHints.email,
            AutofillHints.telephoneNumber,
          ],
        ),
        const SizedBox(height: 14),
        _passwordField(
          _password,
          'Password',
          _showPassword,
          _togglePassword,
          c,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  Widget _signupFields(AlsamosColors c) {
    return Column(
      key: const ValueKey('signup'),
      children: [
        _field(
          _fullName,
          'Full Name',
          LucideIcons.user,
          c,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 14),
        _field(_username, 'Username', LucideIcons.atSign, c,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_]')),
            ],
            toLower: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username]),
        const SizedBox(height: 14),
        _field(
          _identifier,
          'Email',
          LucideIcons.mail,
          c,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 14),
        _passwordField(
          _password,
          'Password',
          _showPassword,
          _togglePassword,
          c,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newPassword],
        ),
        const SizedBox(height: 14),
        _passwordField(
          _confirm,
          'Confirm Password',
          _showConfirm,
          _toggleConfirm,
          c,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  Widget _glow(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      ),
    );
  }

  Widget _modeTab(
      String label, bool active, VoidCallback onTap, AlsamosColors c) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? c.background : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1)),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                  color: active ? c.foreground : c.mutedForeground)),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon,
    AlsamosColors c, {
    List<TextInputFormatter>? inputFormatters,
    bool toLower = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
  }) {
    return TextField(
      controller: ctrl,
      inputFormatters: inputFormatters,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      style: TextStyle(color: c.foreground, fontSize: 14),
      onChanged: toLower
          ? (v) {
              final lower = v.toLowerCase();
              if (lower != v) {
                ctrl.value = ctrl.value.copyWith(
                  text: lower,
                  selection: TextSelection.collapsed(offset: lower.length),
                );
              }
            }
          : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: c.mutedForeground.withValues(alpha: 0.7), fontSize: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(icon, size: 17, color: c.mutedForeground),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: c.muted.withValues(alpha: 0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: c.border.withValues(alpha: 0.7), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _passwordField(
    TextEditingController ctrl,
    String hint,
    bool show,
    VoidCallback onToggle,
    AlsamosColors c, {
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: !show,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      style: TextStyle(color: c.foreground, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: c.mutedForeground.withValues(alpha: 0.7), fontSize: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(LucideIcons.lock, size: 17, color: c.mutedForeground),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: IconButton(
          splashRadius: 18,
          icon: Icon(show ? LucideIcons.eyeOff : LucideIcons.eye,
              size: 17, color: c.mutedForeground),
          onPressed: onToggle,
        ),
        filled: true,
        fillColor: c.muted.withValues(alpha: 0.55),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: c.border.withValues(alpha: 0.7), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _footerLink(String text, AlsamosColors c) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: c.mutedForeground)),
      ),
    );
  }

  Widget _dot(AlsamosColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child:
          Text('•', style: TextStyle(fontSize: 12, color: c.mutedForeground)),
    );
  }
}
