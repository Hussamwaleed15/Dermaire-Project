import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'account/account_controller.dart';
import 'dermaire_state.dart';
import 'dermaire_theme.dart';
import 'dermaire_widgets.dart';
import 'doctor_portal.dart';
import 'entry/safety_consent_controller.dart';
import 'entry/entry_copy.dart';
import 'entry/entry_motion.dart';
import 'entry/entry_widgets.dart';
import 'services/api_service.dart';
import 'services/google_auth_helper.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? _validateEmail(String? value) =>
    _emailPattern.hasMatch(value?.trim() ?? '')
    ? null
    : 'Enter a valid email address';

void _openApp(
  BuildContext context,
  DermaireState state, {
  bool onboarding = false,
}) {
  Navigator.of(context).pushAndRemoveUntil(
    entryRoute(context, PatientEntryGate(state: state, onboarding: onboarding)),
    (_) => false,
  );
}

class PatientEntryGate extends StatefulWidget {
  const PatientEntryGate({
    super.key,
    required this.state,
    this.onboarding = false,
  });
  final DermaireState state;
  final bool onboarding;

  @override
  State<PatientEntryGate> createState() => _PatientEntryGateState();
}

class _PatientEntryGateState extends State<PatientEntryGate> {
  late final SafetyConsentController consent;
  bool _loadedShell = false;
  bool _hydrationStarted = false;
  bool _enteredShell = false;

  @override
  void initState() {
    super.initState();
    widget.state.account.addListener(_changed);
    consent = SafetyConsentController(ApiService.instance)
      ..addListener(_changed);
    unawaited(consent.refresh());
  }

  void _changed() {
    if (!mounted) return;
    if (consent.confirmed && !_hydrationStarted) {
      _hydrationStarted = true;
      // Same-session consent GET supplies the initial authoritative profile.
      unawaited(widget.state.account.hydrate());
    }
    if (consent.confirmed &&
        widget.state.account.ready &&
        !widget.onboarding &&
        _enteredShell &&
        !_loadedShell) {
      _loadedShell = true;
      unawaited(widget.state.productController.load());
      unawaited(widget.state.baseline.refresh());
      unawaited(widget.state.dailyContext.refresh());
      unawaited(widget.state.home.refresh());
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.state.account.removeListener(_changed);
    consent
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  Future<void> _signOut() async {
    // Invalidate immediately; server revocation is bounded and best effort.
    final logout = ApiService.instance.logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => WelcomeScreen(state: widget.state)),
        (_) => false,
      );
    }
    await logout;
  }

  void _continue() {
    // A retained callback cannot unlock another account or an ended session.
    if (!mounted || !consent.confirmed || !widget.state.account.ready) return;
    _enteredShell = true;
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final c = EntryCopy.of(context);
    if (consent.confirmed && widget.state.account.ready) {
      if (widget.onboarding) return AccountCreatedScreen(state: widget.state);
      if (_enteredShell) return AppShell(state: widget.state);
      return EntryStatusPage(
        message: c.success,
        success: true,
        onContinue: _continue,
        continueKey: const Key('continueEntry'),
        onSignOut: _signOut,
      );
    }
    if (consent.confirmed) {
      final account = widget.state.account;
      final loading = account.phase == AccountPhase.loading;
      return EntryStatusPage(
        message: c.profile,
        onSignOut: _signOut,
        error: loading
            ? null
            : account.error ??
                  c.choose(
                    'Your account profile is unavailable.',
                    'ملف الحساب غير متاح.',
                  ),
        onRetry: loading ? null : () => account.hydrate(reuseConsent: false),
        retryKey: const Key('retryAccountProfile'),
      );
    }
    if (consent.current &&
        (consent.phase == ConsentPhase.required ||
            consent.phase == ConsentPhase.accepting)) {
      return SafetyResponsibilityScreen(
        state: widget.state,
        onAccept: consent.accept,
        onSignOut: _signOut,
        acceptanceError: consent.error,
      );
    }
    final checking = consent.phase == ConsentPhase.checking;
    return EntryStatusPage(
      message: c.checking,
      onSignOut: _signOut,
      error: checking
          ? null
          : consent.error ??
                c.choose('Please sign in again.', 'يرجى تسجيل الدخول مجددًا.'),
      onRetry: !checking && consent.current ? consent.refresh : null,
      retryKey: const Key('retrySafetyRead'),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) {
    final c = EntryCopy.of(context);
    final t = EntryTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return EntryPage(
      showBack: false,
      editorial: true,
      eyebrow: c.choose('Personal Skin Health', 'صحة بشرتك'),
      title: c.welcome,
      subtitle: c.welcomeBody,
      headerActions: [
        IconButton(
          key: const Key('languageToggle'),
          tooltip: c.choose('العربية', 'English'),
          onPressed: state.toggleLanguage,
          icon: const Icon(Icons.translate),
        ),
        IconButton(
          key: const Key('themeToggle'),
          tooltip: isDark
              ? c.choose('Light mode', 'الوضع الفاتح')
              : c.choose('Dark mode', 'الوضع الداكن'),
          onPressed: state.toggleTheme,
          icon: Icon(
            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        ),
      ],
      footer: [
        EntryPress(
          child: FilledButton(
            key: const Key('startExperimentButton'),
            onPressed: () =>
                openEntry(context, CreateAccountScreen(state: state)),
            child: Text(c.create),
          ),
        ),
        OutlinedButton(
          key: const Key('existingAccountButton'),
          onPressed: () => openEntry(context, SignInScreen(state: state)),
          child: Text(c.existing),
        ),
      ],
      children: [
        EntryCard(
          child: Column(
            children: [
              Image.asset(
                'assets/images/dermaire-logo.webp',
                width: 112,
                height: 112,
                semanticLabel: 'Dermaire logo',
              ),
              const SizedBox(height: 20),
              ...[
                (Icons.visibility_outlined, c.choose('Observe', 'لاحظ')),
                (Icons.insights_outlined, c.choose('Understand', 'افهم')),
                (Icons.timeline, c.choose('Track', 'تابع')),
              ].map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(item.$1, color: t.action),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          item.$2,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          c.disclosure,
          style: TextStyle(fontSize: 12, color: t.secondary, height: 1.5),
        ),
      ],
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.state, this.googleSignIn});
  final DermaireState state;
  final Future<String?> Function()? googleSignIn;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool hidePassword = true;

  bool loading = false;
  String? authError;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    if (loading) return;
    setState(() {
      loading = true;
      authError = null;
    });
    try {
      final pickerGeneration = ApiService.instance.sessionGeneration;
      final idToken =
          await (widget.googleSignIn ?? GoogleAuthHelper.signInAndGetIdToken)();
      if (!mounted ||
          pickerGeneration != ApiService.instance.sessionGeneration) {
        return;
      }
      if (idToken == null) {
        // User cancelled the Google account picker — not an error.
        return;
      }
      final login = ApiService.instance.loginWithGoogle(idToken: idToken);
      final generation = ApiService.instance.sessionGeneration;
      await login;
      if (!mounted || !ApiService.instance.isCurrentSession(generation)) return;
      _openApp(context, widget.state);
    } catch (e) {
      if (!mounted) return;
      setState(() => authError = EntryCopy.of(context).authError);
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> submit() async {
    if (loading || !(formKey.currentState?.validate() ?? false)) return;
    setState(() {
      loading = true;
      authError = null;
    });
    try {
      final login = ApiService.instance.login(
        email: email.text.trim(),
        password: password.text.trim(),
      );
      final generation = ApiService.instance.sessionGeneration;
      await login;
      if (!mounted || !ApiService.instance.isCurrentSession(generation)) return;
      _openApp(context, widget.state);
    } catch (e) {
      if (!mounted) return;
      setState(() => authError = EntryCopy.of(context).authError);
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EntryCopy.of(context);
    if (loading || authError != null) {
      return EntryStatusPage(
        message: c.signingIn,
        error: authError,
        onSignOut: () async {
          final logout = ApiService.instance.logout();
          Navigator.of(context).pushAndRemoveUntil(
            entryRoute(context, WelcomeScreen(state: widget.state)),
            (_) => false,
          );
          await logout;
        },
        onRetry: authError == null
            ? null
            : () => setState(() => authError = null),
        retryKey: const Key('signInButton'),
      );
    }
    return EntryPage(
      eyebrow: c.choose('Welcome back', 'مرحبًا بعودتك'),
      title: c.choose('Your journey continues here.', 'رحلتك تستمر من هنا.'),
      subtitle: c.choose(
        'Sign in to your private skin history.',
        'سجّل الدخول إلى سجل بشرتك الخاص.',
      ),
      footer: [
        EntryPress(
          child: FilledButton(
            key: const Key('signInButton'),
            onPressed: loading ? null : submit,
            child: Text(c.signIn),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            entryRoute(context, CreateAccountScreen(state: widget.state)),
          ),
          child: Text(c.create),
        ),
        TextButton.icon(
          onPressed: () => openEntry(context, const DoctorSignInScreen()),
          icon: const Icon(Icons.medical_services_outlined),
          label: Text(c.choose('Clinician sign in', 'دخول الطبيب')),
        ),
      ],
      children: [
        _SocialButton(
          iconWidget: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const Text(
              'G',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.redAccent,
              ),
            ),
          ),
          label: c.google,
          onPressed: loading ? null : _signInWithGoogle,
        ),
        const _OrDivider(),
        Form(
          key: formKey,
          child: Column(
            children: [
              EntryField(
                child: TextFormField(
                  key: const Key('signInEmail'),
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: c.email),
                  validator: (value) =>
                      _validateEmail(value) == null ? null : c.validEmail,
                ),
              ),
              const SizedBox(height: 12),
              EntryField(
                child: TextFormField(
                  key: const Key('signInPassword'),
                  controller: password,
                  obscureText: hidePassword,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    labelText: c.password,
                    suffixIcon: IconButton(
                      tooltip: c.choose(
                        hidePassword ? 'Show password' : 'Hide password',
                        hidePassword
                            ? 'إظهار كلمة المرور'
                            : 'إخفاء كلمة المرور',
                      ),
                      onPressed: () =>
                          setState(() => hidePassword = !hidePassword),
                      icon: Icon(
                        hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      (value?.isNotEmpty ?? false) ? null : c.passwordRequired,
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () =>
                openEntry(context, ForgotPasswordScreen(state: widget.state)),
            child: Text(c.choose('Forgot password?', 'نسيت كلمة المرور؟')),
          ),
        ),
      ],
    );
  }
}

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    required this.state,
    this.googleSignIn,
  });
  final DermaireState state;
  final Future<String?> Function()? googleSignIn;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool hidePassword = true;
  bool hideConfirmation = true;
  bool loading = false;
  String? authError;

  int get strength {
    final value = password.text;
    var score = 0;
    if (value.length >= 8) score++;
    if (RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score;
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  void createAccount() {
    if (loading || !(formKey.currentState?.validate() ?? false)) return;
    openEntry(
      context,
      SafetyResponsibilityScreen(
        state: widget.state,
        email: email.text.trim(),
        password: password.text.trim(),
      ),
    );
  }

  Future<void> _signUpWithGoogle() async {
    if (loading) return;
    setState(() {
      loading = true;
      authError = null;
    });
    try {
      final pickerGeneration = ApiService.instance.sessionGeneration;
      final idToken =
          await (widget.googleSignIn ?? GoogleAuthHelper.signInAndGetIdToken)();
      if (!mounted ||
          pickerGeneration != ApiService.instance.sessionGeneration) {
        return;
      }
      if (idToken == null) return; // user cancelled the account picker
      final login = ApiService.instance.loginWithGoogle(idToken: idToken);
      final generation = ApiService.instance.sessionGeneration;
      await login;
      if (!mounted || !ApiService.instance.isCurrentSession(generation)) return;
      _openApp(context, widget.state, onboarding: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => authError = EntryCopy.of(context).authError);
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EntryCopy.of(context);
    if (loading || authError != null) {
      return EntryStatusPage(
        message: c.signingIn,
        error: authError,
        onSignOut: () async {
          final logout = ApiService.instance.logout();
          Navigator.of(context).pushAndRemoveUntil(
            entryRoute(context, WelcomeScreen(state: widget.state)),
            (_) => false,
          );
          await logout;
        },
        onRetry: authError == null
            ? null
            : () => setState(() => authError = null),
        retryKey: const Key('signInButton'),
      );
    }
    return EntryPage(
      eyebrow: c.choose('Your private skin health', 'صحة بشرتك بخصوصية'),
      title: c.create,
      subtitle: c.choose(
        'Your private skin health account.',
        'حسابك الخاص لصحة بشرتك.',
      ),
      footer: [
        const SizedBox(height: 16),
        EntryPress(
          child: FilledButton(
            key: const Key('createAccountButton'),
            onPressed: createAccount,
            child: Text(c.choose('Continue to safety', 'المتابعة إلى السلامة')),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            entryRoute(context, SignInScreen(state: widget.state)),
          ),
          child: Text(
            c.choose(
              'Already have an account? Sign in',
              'لديك حساب بالفعل؟ سجّل الدخول',
            ),
          ),
        ),
      ],
      children: [
        _SocialButton(
          iconWidget: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const Text(
              'G',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.redAccent,
              ),
            ),
          ),
          label: c.choose('Sign up with Google', 'التسجيل باستخدام Google'),
          onPressed: loading ? null : _signUpWithGoogle,
        ),
        const _OrDivider(),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EntryField(
                child: TextFormField(
                  key: const Key('createEmail'),
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.newUsername],
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(labelText: c.email),
                  validator: (value) =>
                      _validateEmail(value) == null ? null : c.validEmail,
                ),
              ),
              const SizedBox(height: 12),
              EntryField(
                child: TextFormField(
                  key: const Key('createPassword'),
                  controller: password,
                  obscureText: hidePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: c.password,
                    suffixIcon: IconButton(
                      tooltip: c.choose(
                        hidePassword ? 'Show password' : 'Hide password',
                        hidePassword
                            ? 'إظهار كلمة المرور'
                            : 'إخفاء كلمة المرور',
                      ),
                      onPressed: () =>
                          setState(() => hidePassword = !hidePassword),
                      icon: Icon(
                        hidePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (_) => strength >= 3 ? null : c.passwordRules,
                ),
              ),
              const SizedBox(height: 8),
              _PasswordStrength(value: strength),
              const SizedBox(height: 12),
              EntryField(
                child: TextFormField(
                  key: const Key('confirmPassword'),
                  controller: confirmPassword,
                  obscureText: hideConfirmation,
                  onFieldSubmitted: (_) => createAccount(),
                  decoration: InputDecoration(
                    labelText: c.confirm,
                    suffixIcon: IconButton(
                      tooltip: c.choose(
                        hideConfirmation ? 'Show password' : 'Hide password',
                        hideConfirmation
                            ? 'إظهار كلمة المرور'
                            : 'إخفاء كلمة المرور',
                      ),
                      onPressed: () =>
                          setState(() => hideConfirmation = !hideConfirmation),
                      icon: Icon(
                        hideConfirmation
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      value == password.text && value!.isNotEmpty
                      ? null
                      : c.choose(
                          'Passwords do not match',
                          'كلمتا المرور غير متطابقتين',
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.iconWidget,
    required this.label,
    required this.onPressed,
  });
  final Widget iconWidget;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: iconWidget,
    label: Text(label),
  );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            EntryCopy.of(context).choose('OR', 'أو'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: .55),
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    ),
  );
}

class _PasswordStrength extends StatelessWidget {
  const _PasswordStrength({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final c = EntryCopy.of(context);
    final label = c.choose(
      ['Password strength', 'Weak', 'Fair', 'Strong', 'Very strong'][value],
      ['قوة كلمة المرور', 'ضعيفة', 'متوسطة', 'قوية', 'قوية جدًا'][value],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(
            4,
            (index) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index == 3 ? 0 : 5),
                decoration: BoxDecoration(
                  color: index < value ? color : Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: color)),
      ],
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.state});
  final DermaireState state;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final resetToken = TextEditingController();
  final newPassword = TextEditingController();
  bool sent = false;
  bool loading = false;
  bool resetDone = false;
  String? devNote;
  String? errorText;

  @override
  void dispose() {
    email.dispose();
    resetToken.dispose();
    newPassword.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!formKey.currentState!.validate() || loading) return;
    setState(() {
      loading = true;
      errorText = null;
    });
    try {
      final data = await ApiService.instance.forgotPassword(
        email: email.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        sent = true;
        devNote = data['note']?.toString();
        if (data['reset_token'] != null) {
          resetToken.text = data['reset_token'].toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => errorText = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    if (resetToken.text.trim().isEmpty || newPassword.text.trim().length < 8) {
      setState(
        () => errorText =
            'Enter the reset code and a password of at least 8 characters.',
      );
      return;
    }
    setState(() {
      loading = true;
      errorText = null;
    });
    try {
      await ApiService.instance.resetPassword(
        email: email.text.trim(),
        token: resetToken.text.trim(),
        newPassword: newPassword.text.trim(),
      );
      if (!mounted) return;
      setState(() => resetDone = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorText = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Account recovery',
    title: 'Forgot password',
    subtitle: resetDone
        ? 'Your password has been updated.'
        : sent
        ? 'Enter the reset code and choose a new password.'
        : 'Enter your email and we’ll send you a reset code.',
    children: [
      if (resetDone) ...[
        const Notice(
          icon: '✓',
          text:
              'Password reset successful. You can sign in with your new password now.',
          color: DermaireColors.safeBackground,
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ] else if (!sent) ...[
        Form(
          key: formKey,
          child: TextFormField(
            key: const Key('resetEmail'),
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: _validateEmail,
          ),
        ),
        const SizedBox(height: 14),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: loading ? null : _sendResetLink,
          child: Text(loading ? 'Sending…' : 'Send reset code'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ] else ...[
        const Notice(
          icon: '✓',
          text:
              'If an account exists for this email, a reset code has been sent.',
          color: DermaireColors.safeBackground,
        ),
        if (devNote != null) ...[
          const SizedBox(height: 10),
          Text(devNote!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: resetToken,
          decoration: const InputDecoration(labelText: 'Reset code'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: newPassword,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password'),
        ),
        const SizedBox(height: 14),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: loading ? null : _submitNewPassword,
          child: Text(loading ? 'Saving…' : 'Set new password'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to sign in'),
        ),
      ],
    ],
  );
}

class SafetyResponsibilityScreen extends StatefulWidget {
  const SafetyResponsibilityScreen({
    super.key,
    required this.state,
    this.email,
    this.password,
    this.onAccept,
    this.onSignOut,
    this.acceptanceError,
  });
  final DermaireState state;
  final String? email;
  final String? password;
  final Future<void> Function()? onAccept;
  final VoidCallback? onSignOut;
  final String? acceptanceError;

  @override
  State<SafetyResponsibilityScreen> createState() =>
      _SafetyResponsibilityScreenState();
}

class _SafetyResponsibilityScreenState
    extends State<SafetyResponsibilityScreen> {
  final controller = ScrollController();
  bool reachedEnd = false;
  bool loading = false;
  String? error;

  Future<void> _acceptSafety() async {
    if (!reachedEnd || loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.onAccept != null) {
        await widget.onAccept!();
        return;
      }
      final api = ApiService.instance;
      if (widget.email != null && widget.password != null) {
        final registration = api.register(
          email: widget.email!,
          password: widget.password!,
          fullName: 'Dermaire Member',
          acceptSafety: true,
        );
        final generation = api.sessionGeneration;
        await registration;
        if (!mounted || !api.isCurrentSession(generation)) return;
        // Readback/retries now belong to the gate, never a second register POST.
        _openApp(context, widget.state, onboarding: true);
      } else {
        final generation = api.sessionGeneration;
        await api.acceptSafetyTerms();
        final accepted = await api.readSafetyAcceptance();
        if (!mounted || !api.isCurrentSession(generation)) return;
        if (!accepted) {
          throw ApiException(
            'The server has not confirmed your acceptance. Please retry.',
          );
        }
        _openApp(context, widget.state);
      }
    } catch (failure) {
      if (!mounted) return;
      setState(
        () => error = failure is ApiException
            ? failure.message
            : 'Safety acceptance could not be confirmed. Please retry.',
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_checkScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkScroll());
  }

  void _checkScroll() {
    if (!controller.hasClients || reachedEnd) return;
    if (controller.position.maxScrollExtent <= 0 ||
        controller.position.extentAfter <= 4) {
      setState(() => reachedEnd = true);
    }
  }

  @override
  void dispose() {
    controller
      ..removeListener(_checkScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = EntryCopy.of(context);
    if (loading) {
      return EntryStatusPage(
        message: c.choose('Confirming your acceptance…', 'جارٍ تأكيد موافقتك…'),
        onSignOut: widget.onSignOut,
      );
    }
    return EntryPage(
      showBack: widget.onAccept == null,
      scrollKey: const Key('safetyScroll'),
      controller: controller,
      eyebrow: c.choose('Safety before you begin', 'السلامة قبل البدء'),
      title: c.choose('Safety & responsibility', 'السلامة والمسؤولية'),
      subtitle: c.choose(
        'Read these notes before you continue.',
        'اقرأ هذه الإرشادات قبل المتابعة.',
      ),
      footer: [
        if (!reachedEnd)
          Text(
            c.choose(
              'Scroll to the end to continue',
              'مرّر إلى النهاية للمتابعة',
            ),
            style: TextStyle(
              color: EntryTokens.of(context).secondary,
              fontSize: 12,
            ),
          ),
        if (error != null || widget.acceptanceError != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error ?? widget.acceptanceError!,
              key: const Key('safetyError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        EntryPress(
          child: FilledButton(
            key: const Key('acceptSafetyButton'),
            onPressed: reachedEnd && !loading ? _acceptSafety : null,
            child: Text(c.choose('I understand — continue', 'فهمت — متابعة')),
          ),
        ),
        if (widget.onSignOut != null)
          TextButton(
            key: const Key('consentSignOut'),
            onPressed: widget.onSignOut,
            child: Text(c.signOut),
          ),
      ],
      children: [
        const _SafetyItem(
          icon: Icons.health_and_safety_outlined,
          title: 'Dermaire is not medical advice',
          text:
              'The app helps you observe patterns. It does not diagnose, treat, or replace a dermatologist or other qualified clinician.',
        ),
        const _SafetyItem(
          icon: Icons.science_outlined,
          title: 'Change one thing at a time',
          text:
              'Patch test new products first. Introduce one product per experiment so you can identify what caused a change.',
        ),
        const _SafetyItem(
          icon: Icons.warning_amber_rounded,
          title: 'Stop if irritation appears',
          text:
              'Stop the experiment if you develop burning, swelling, severe redness, blistering, or rapidly worsening symptoms.',
        ),
        const _SafetyItem(
          icon: Icons.local_hospital_outlined,
          title: 'Know when to seek care',
          text:
              'Seek urgent medical help for trouble breathing, facial swelling, widespread hives, eye involvement, or another severe reaction.',
        ),
        const _SafetyItem(
          icon: Icons.lock_outline,
          title: 'Protect your information',
          text:
              'Use the app on your own device, secure your account, and avoid including identifying information in notes you plan to share.',
        ),
        DermaireCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.choose('Disclaimer', 'إخلاء مسؤولية'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                c.choose(
                  'Skin measurements can vary with lighting, camera quality, environment, routine, and normal biological changes. Results are estimates and may be incomplete or inaccurate. You remain responsible for product choices and for following each manufacturer’s instructions. If you are pregnant, breastfeeding, have a diagnosed skin condition, use prescription treatment, or are unsure whether an ingredient is suitable, speak with a qualified clinician before beginning an experiment.',
                  'قد تختلف قياسات البشرة باختلاف الإضاءة وجودة الكاميرا والبيئة والروتين والتغيّرات البيولوجية الطبيعية. النتائج تقديرات وقد تكون ناقصة أو غير دقيقة. تظل مسؤولًا عن اختيار المنتجات واتباع تعليمات كل شركة مصنّعة. إذا كنتِ حاملًا أو مرضعة، أو لديك حالة جلدية مشخصة، أو تستخدم علاجًا بوصفة طبية، أو لم تكن متأكدًا من ملاءمة أحد المكوّنات، استشر مختصًا مؤهلًا قبل بدء أي تجربة.',
                ),
                style: TextStyle(fontSize: 12.5, height: 1.55),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SafetyItem extends StatelessWidget {
  const _SafetyItem({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: DermaireColors.caramel.withValues(alpha: .3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: icon == Icons.local_hospital_outlined
                ? Theme.of(context).colorScheme.error
                : icon == Icons.warning_amber_rounded
                ? (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFFF4D18B)
                      : const Color(0xFF75520F))
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                EntryCopy.of(
                  context,
                ).choose(title, _safetyArabic[title] ?? title),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                EntryCopy.of(context).choose(text, _safetyArabic[text] ?? text),
                style: const TextStyle(fontSize: 12.5, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class AccountCreatedScreen extends StatelessWidget {
  const AccountCreatedScreen({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) {
    final c = EntryCopy.of(context);
    final generation = ApiService.instance.sessionGeneration;
    return EntryStatusPage(
      message: c.success,
      success: true,
      onSignOut: null,
      continueKey: const Key('continueRegistration'),
      onContinue: () {
        if (!ApiService.instance.isCurrentSession(generation) ||
            !ApiService.instance.hasConfirmedSafetyAcceptance ||
            !state.account.ready) {
          return;
        }
        Navigator.of(
          context,
        ).pushReplacement(entryRoute(context, SkinProfileScreen(state: state)));
      },
    );
  }
}

class SkinProfileScreen extends StatefulWidget {
  const SkinProfileScreen({
    super.key,
    required this.state,
    this.editing = false,
  });
  final DermaireState state;
  final bool editing;
  @override
  State<SkinProfileScreen> createState() => _SkinProfileScreenState();
}

class _SkinProfileScreenState extends State<SkinProfileScreen> {
  Map<String, dynamic>? get profile =>
      ApiService.instance.isCurrentSession(generation)
      ? widget.state.account.value?.editorFields
      : null;
  late final int generation;
  bool _disposed = false;
  final draft = <String, dynamic>{};
  final contextDraft = <String, dynamic>{};
  String? error;
  bool saving = false;
  bool savedAwaitingRefresh = false;
  int section = 0;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    widget.state.account.addListener(_accountChanged);
    if (!widget.state.account.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) load();
      });
    }
  }

  void _accountChanged() {
    if (!mounted || _disposed) return;
    if (!ApiService.instance.isCurrentSession(generation)) {
      draft.clear();
      contextDraft.clear();
      error = 'Your session changed. Please sign in again.';
    }
    setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    draft.clear();
    contextDraft.clear();
    widget.state.account.removeListener(_accountChanged);
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted || !ApiService.instance.isCurrentSession(generation)) return;
    setState(() {
      error = null;
    });
    await widget.state.account.hydrate(reuseConsent: false);
    if (mounted && ApiService.instance.isCurrentSession(generation)) {
      setState(() {
        error = widget.state.account.error;
        if (widget.state.account.ready) savedAwaitingRefresh = false;
      });
    }
  }

  dynamic value(String key, {bool root = false}) {
    final source = root ? draft : contextDraft;
    if (source.containsKey(key)) return source[key];
    if (root) return profile?[key];
    final saved = profile?['profile_context'] as Map?;
    return saved?[key];
  }

  Widget choice(
    String key,
    String label,
    Map<String, String> options, {
    bool root = false,
  }) {
    final selected = value(key, root: root) as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$key:$selected'),
        initialValue: options.containsKey(selected) ? selected : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: '$label (optional)'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Not shared / clear')),
          ...options.entries.map(
            (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
          ),
        ],
        onChanged: saving
            ? null
            : (v) => setState(() {
                savedAwaitingRefresh = false;
                (root ? draft : contextDraft)[key] = v == '' ? null : v;
                if (key == 'hormonal_disclosure') {
                  contextDraft['hormonal_context'] = null;
                }
              }),
      ),
    );
  }

  Widget entries(String key, String label, {bool root = false}) {
    final values = (value(key, root: root) as List?)?.cast<String>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey(key),
        initialValue: values?.join(', ') ?? '',
        enabled: !saving,
        maxLength: 1000,
        decoration: InputDecoration(
          labelText: '$label (optional)',
          helperText: 'Separate entries with commas. Clear to remove.',
        ),
        onChanged: (v) {
          if (savedAwaitingRefresh) {
            setState(() => savedAwaitingRefresh = false);
          }
          (root ? draft : contextDraft)[key] = v.trim().isEmpty
              ? []
              : v
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
        },
      ),
    );
  }

  Future<void> save() async {
    if (saving || !ApiService.instance.isCurrentSession(generation)) return;
    setState(() {
      saving = true;
      error = null;
    });
    final result = await widget.state.account.save({
      ...draft,
      if (contextDraft.isNotEmpty) 'profile_context': Map.of(contextDraft),
    });
    if (!mounted || !ApiService.instance.isCurrentSession(generation)) return;
    if (result == ProfileSaveResult.saved) {
      draft.clear();
      contextDraft.clear();
      if (widget.editing) {
        Navigator.of(context).pop();
      } else {
        _openApp(context, widget.state);
      }
    } else {
      if (result == ProfileSaveResult.savedReadbackUnavailable) {
        draft.clear();
        contextDraft.clear();
        savedAwaitingRefresh = true;
      }
      setState(() {
        saving = false;
        error = widget.state.account.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Skin profile',
    title: [
      'Tell us about your skin',
      'Care and goals',
      'Optional context',
    ][section],
    subtitle:
        'Share only what you choose. These answers will provide context for a future personal skin model. No sensitive information is inferred.',
    children: [
      if (error != null || widget.state.account.error != null)
        Text(
          error ?? widget.state.account.error!,
          key: const Key('profileError'),
        ),
      if (error == 'Profile saved; latest view unavailable. Retry refresh.')
        TextButton(onPressed: load, child: const Text('Retry refresh')),
      if (profile == null) ...[
        if (ApiService.instance.isCurrentSession(generation) &&
            widget.state.account.phase == AccountPhase.loading)
          const Center(child: CircularProgressIndicator())
        else if (ApiService.instance.isCurrentSession(generation))
          TextButton(onPressed: load, child: const Text('Retry')),
        if (!ApiService.instance.isCurrentSession(generation))
          const Text('Please sign in again.'),
      ] else ...[
        if (section == 0) ...[
          const Text(
            'Skin type and concerns help organize the changes you want to track. Blank means not shared.',
          ),
          choice('skin_type', 'Skin type', {
            'dry': 'Dry',
            'oily': 'Oily',
            'combination': 'Combination',
            'normal': 'Normal',
            'sensitive': 'Sensitive',
          }, root: true),
          entries('skin_concerns', 'Skin concerns', root: true),
          entries('sensitivities_allergies', 'Known sensitivities / allergies'),
          const Text(
            'Known reactions help distinguish tolerated products from reported triggers. Empty entries do not mean no allergies.',
          ),
        ],
        if (section == 1) ...[
          const Text(
            'Care and treatment details provide context for skin changes. Goals define what you want to track.',
          ),
          choice('dermatologist_care', 'Dermatologist care', {
            'current': 'Currently receiving care',
            'past': 'Previously received care',
            'never': 'Never received care',
            'prefer_not_to_say': 'Prefer not to say',
          }),
          entries('medications_treatments', 'Skin medications / treatments'),
          entries('primary_goals', 'Primary goals'),
        ],
        if (section == 2) ...[
          const Text(
            'Age group and disclosed sex provide physiological context. Hormonal and menstrual context may help contextualize changes over time. All are optional; cycle questions are available to everyone without assuming applicability.',
          ),
          choice('age_band', 'Age group', {
            'under_18': 'Under 18',
            '18_24': '18–24',
            '25_34': '25–34',
            '35_44': '35–44',
            '45_54': '45–54',
            '55_64': '55–64',
            '65_plus': '65+',
            'prefer_not_to_say': 'Prefer not to say',
          }),
          choice('sex', 'Sex', {
            'female': 'Female',
            'male': 'Male',
            'intersex': 'Intersex',
            'prefer_not_to_say': 'Prefer not to say',
          }),
          choice('hormonal_disclosure', 'Hormonal context', {
            'disclosed': 'Choose context to share',
            'none_reported': 'No relevant context reported',
            'prefer_not_to_say': 'Prefer not to say',
          }),
          if (value('hormonal_disclosure') == 'disclosed')
            Wrap(
              children:
                  {
                    'puberty': 'Puberty',
                    'pregnancy': 'Pregnancy',
                    'postpartum': 'Postpartum',
                    'perimenopause': 'Perimenopause',
                    'menopause': 'Menopause',
                    'hormonal_contraception': 'Hormonal contraception',
                    'hormone_therapy': 'Hormone therapy',
                  }.entries.map((e) {
                    final selected = List<String>.from(
                      value('hormonal_context') as List? ?? [],
                    );
                    return FilterChip(
                      label: Text(e.value),
                      selected: selected.contains(e.key),
                      onSelected: saving
                          ? null
                          : (on) => setState(() {
                              on ? selected.add(e.key) : selected.remove(e.key);
                              contextDraft['hormonal_context'] = selected;
                            }),
                    );
                  }).toList(),
            ),
          choice('menstrual_context', 'Menstrual cycle context', {
            'regular': 'Regular cycles',
            'irregular': 'Irregular cycles',
            'not_menstruating': 'Not menstruating',
            'not_applicable': 'Not applicable',
            'prefer_not_to_say': 'Prefer not to say',
          }),
        ],
        if (section > 0)
          TextButton(
            onPressed: saving
                ? null
                : () => setState(() {
                    section--;
                  }),
            child: const Text('Back'),
          ),
        if (section < 2)
          TextButton(
            onPressed: saving
                ? null
                : () => setState(() {
                    section++;
                  }),
            child: const Text('Next optional section'),
          ),
        FilledButton(
          key: const Key('saveProfile'),
          onPressed: saving || savedAwaitingRefresh ? null : save,
          child: Text(saving ? 'Saving…' : 'Save and continue'),
        ),
        TextButton(
          onPressed: saving
              ? null
              : () {
                  if (widget.editing) {
                    Navigator.of(context).pop();
                  } else {
                    _openApp(context, widget.state);
                  }
                },
          child: const Text('Skip / keep saved profile'),
        ),
      ],
    ],
  );
}

const _safetyArabic = <String, String>{
  'Dermaire is not medical advice': 'Dermaire لا يقدّم نصيحة طبية',
  'The app helps you observe patterns. It does not diagnose, treat, or replace a dermatologist or other qualified clinician.':
      'يساعدك التطبيق على ملاحظة الأنماط. لا يشخّص أو يعالج، ولا يحلّ محل طبيب الجلدية أو أي مختص مؤهل.',
  'Change one thing at a time': 'غيّر شيئًا واحدًا في كل مرة',
  'Patch test new products first. Introduce one product per experiment so you can identify what caused a change.':
      'اختبر المنتجات الجديدة على مساحة صغيرة أولًا. أدخل منتجًا واحدًا في كل تجربة لتتمكن من معرفة سبب التغيّر.',
  'Stop if irritation appears': 'توقّف عند ظهور تهيّج',
  'Stop the experiment if you develop burning, swelling, severe redness, blistering, or rapidly worsening symptoms.':
      'أوقف التجربة إذا ظهر حرقان أو تورّم أو احمرار شديد أو بثور أو أعراض تتفاقم بسرعة.',
  'Know when to seek care': 'اعرف متى تطلب الرعاية',
  'Seek urgent medical help for trouble breathing, facial swelling, widespread hives, eye involvement, or another severe reaction.':
      'اطلب مساعدة طبية عاجلة عند صعوبة التنفّس أو تورّم الوجه أو طفح منتشر أو تأثّر العين أو أي تفاعل شديد آخر.',
  'Protect your information': 'احمِ معلوماتك',
  'Use the app on your own device, secure your account, and avoid including identifying information in notes you plan to share.':
      'استخدم التطبيق على جهازك الشخصي، وأمّن حسابك، وتجنّب ذكر معلومات تحدد هويتك في الملاحظات التي تخطط لمشاركتها.',
};
