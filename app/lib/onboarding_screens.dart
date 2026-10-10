import 'dart:async';

import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'capture/photo_disclosure.dart';
import 'dermaire_state.dart';
import 'dermaire_theme.dart';
import 'dermaire_widgets.dart';
import 'doctor_portal.dart';
import 'services/api_service.dart';
import 'services/google_auth_helper.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? _validateEmail(String? value) =>
    _emailPattern.hasMatch(value?.trim() ?? '')
    ? null
    : 'Enter a valid email address';

void _openApp(BuildContext context, DermaireState state) {
  if (ApiService.instance.isAuthenticated) {
    unawaited(state.productController.load());
    unawaited(state.baseline.refresh());
    unawaited(state.dailyContext.refresh());
    unawaited(state.home.refresh());
  }
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => AppShell(state: state)),
    (_) => false,
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.state});
  final DermaireState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton.filledTonal(
                          key: const Key('themeToggle'),
                          tooltip: isDark ? 'Light mode' : 'Dark mode',
                          onPressed: state.toggleTheme,
                          icon: Icon(
                            isDark ? Icons.light_mode : Icons.dark_mode,
                          ),
                        ),
                      ),
                      const Eyebrow('Personal Skin Lab'),
                      Text(
                        'Dermaire',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineLarge?.copyWith(fontSize: 30),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Understand what actually works for your skin — measure, experiment, learn.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: .72),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? DermaireColors.darkPaper
                                : DermaireColors.paper,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: DermaireColors.caramel,
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SizedBox(
                            height: 160,
                            child: Image.asset(
                              'assets/images/dermaire-logo.webp',
                              fit: BoxFit.contain,
                              semanticLabel: 'Dermaire logo',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        key: const Key('startExperimentButton'),
                        onPressed: () => openPage(
                          context,
                          CreateAccountScreen(state: state),
                        ),
                        child: const Text('Start my skin experiment'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        key: const Key('existingAccountButton'),
                        onPressed: () =>
                            openPage(context, SignInScreen(state: state)),
                        child: const Text('I already have an account'),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        photoUploadDisclosure,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onSurface.withValues(alpha: .58),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.state});
  final DermaireState state;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool hidePassword = true;

  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final idToken = await GoogleAuthHelper.signInAndGetIdToken();
      if (idToken == null) {
        // User cancelled the Google account picker — not an error.
        return;
      }
      await ApiService.instance.loginWithGoogle(idToken: idToken);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign-in failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (!mounted) return;
    _openApp(context, widget.state);
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate() || loading) return;
    setState(() => loading = true);
    try {
      await ApiService.instance.login(
        email: email.text.trim(),
        password: password.text.trim(),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign-in failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (!mounted) return;
    _openApp(context, widget.state);
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Welcome back',
    title: 'Sign in',
    subtitle: 'Continue your private skin experiments.',
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
        label: 'Continue with Google',
        onPressed: loading ? null : _signInWithGoogle,
      ),
      const _OrDivider(),
      Form(
        key: formKey,
        child: Column(
          children: [
            TextFormField(
              key: const Key('signInEmail'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: _validateEmail,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('signInPassword'),
              controller: password,
              obscureText: hidePassword,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => hidePassword = !hidePassword),
                  icon: Icon(
                    hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) =>
                  (value?.isNotEmpty ?? false) ? null : 'Enter your password',
            ),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () =>
              openPage(context, ForgotPasswordScreen(state: widget.state)),
          child: const Text('Forgot password?'),
        ),
      ),
      FilledButton(
        key: const Key('signInButton'),
        onPressed: loading ? null : submit,
        child: Text(loading ? 'Please wait...' : 'Sign in'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => CreateAccountScreen(state: widget.state),
          ),
        ),
        child: const Text('Create account'),
      ),
      TextButton.icon(
        onPressed: () => openPage(context, const DoctorSignInScreen()),
        icon: const Icon(Icons.medical_services_outlined),
        label: const Text('Clinician sign in'),
      ),
    ],
  );
}

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key, required this.state});
  final DermaireState state;

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
    if (!formKey.currentState!.validate()) return;
    final next = widget.state.safetyAccepted
        ? AccountCreatedScreen(state: widget.state)
        : SafetyResponsibilityScreen(
            state: widget.state,
            email: email.text.trim(),
            password: password.text.trim(),
          );
    openPage(context, next);
  }

  Future<void> _signUpWithGoogle() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final idToken = await GoogleAuthHelper.signInAndGetIdToken();
      if (idToken == null) return; // user cancelled the account picker
      await ApiService.instance.loginWithGoogle(idToken: idToken);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign-in failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (!mounted) return;
    // The account already exists on the backend at this point — only the
    // local safety-acceptance step (if not already done on this device) is
    // left before opening the app.
    final next = widget.state.safetyAccepted
        ? AccountCreatedScreen(state: widget.state)
        : SafetyResponsibilityScreen(state: widget.state);
    openPage(context, next);
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    eyebrow: 'Your private skin lab',
    title: 'Create account',
    subtitle: 'Set up your account, then choose what you want to improve.',
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
        label: 'Sign up with Google',
        onPressed: loading ? null : _signUpWithGoogle,
      ),
      const _OrDivider(),
      Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              key: const Key('createEmail'),
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.newUsername],
              decoration: const InputDecoration(labelText: 'Email'),
              validator: _validateEmail,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('createPassword'),
              controller: password,
              obscureText: hidePassword,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  onPressed: () => setState(() => hidePassword = !hidePassword),
                  icon: Icon(
                    hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (_) => strength >= 3
                  ? null
                  : 'Use 8+ characters with upper, lower and a number',
            ),
            const SizedBox(height: 8),
            _PasswordStrength(value: strength),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('confirmPassword'),
              controller: confirmPassword,
              obscureText: hideConfirmation,
              onFieldSubmitted: (_) => createAccount(),
              decoration: InputDecoration(
                labelText: 'Confirm password',
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => hideConfirmation = !hideConfirmation),
                  icon: Icon(
                    hideConfirmation
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => value == password.text && value!.isNotEmpty
                  ? null
                  : 'Passwords do not match',
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('createAccountButton'),
        onPressed: createAccount,
        child: const Text('Create account'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SignInScreen(state: widget.state)),
        ),
        child: const Text('Already have an account? Sign in'),
      ),
    ],
  );
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
            'OR',
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
    final color = switch (value) {
      0 || 1 => DermaireColors.conflict,
      2 => DermaireColors.unknown,
      _ => DermaireColors.safe,
    };
    final label = switch (value) {
      0 => 'Password strength',
      1 => 'Weak',
      2 => 'Fair',
      3 => 'Strong',
      _ => 'Very strong',
    };
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
  });
  final DermaireState state;
  final String? email;
  final String? password;

  @override
  State<SafetyResponsibilityScreen> createState() =>
      _SafetyResponsibilityScreenState();
}

class _SafetyResponsibilityScreenState
    extends State<SafetyResponsibilityScreen> {
  final controller = ScrollController();
  bool reachedEnd = false;
  bool loading = false;

  Future<void> _acceptSafety() async {
    if (!reachedEnd || loading) return;
    setState(() => loading = true);
    try {
      if (widget.email != null && widget.password != null) {
        try {
          await ApiService.instance.register(
            email: widget.email!,
            password: widget.password!,
            fullName: 'Dermaire Member',
            acceptSafety: true,
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Registration failed. Please try again: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }
      }
      // Persist local acceptance only after registration succeeds, or when
      // this is the safety-only flow for an already authenticated account.
      await widget.state.acceptSafety();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AccountCreatedScreen(state: widget.state),
        ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const Key('safetyScroll'),
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('First-time setup'),
                  Text(
                    'Safety & responsibility',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(fontSize: 23),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Please read this once before starting your first skin experiment.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .72),
                    ),
                  ),
                  const SizedBox(height: 18),
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
                          'Disclaimer',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Skin measurements can vary with lighting, camera quality, environment, routine, and normal biological changes. Results are estimates and may be incomplete or inaccurate. You remain responsible for product choices and for following each manufacturer’s instructions. If you are pregnant, breastfeeding, have a diagnosed skin condition, use prescription treatment, or are unsure whether an ingredient is suitable, speak with a qualified clinician before beginning an experiment.',
                          style: TextStyle(fontSize: 12.5, height: 1.55),
                        ),
                      ],
                    ),
                  ),
                  const Notice(
                    icon: '↓',
                    text:
                        'You’ve reached the end. Continue to confirm that you have read these safety notes.',
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              children: [
                if (!reachedEnd)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Scroll to the end to continue',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: .62),
                      ),
                    ),
                  ),
                FilledButton(
                  key: const Key('acceptSafetyButton'),
                  onPressed: reachedEnd && !loading ? _acceptSafety : null,
                  child: Text(
                    loading ? 'Please wait...' : 'I understand — continue',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
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
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 12.5, height: 1.45)),
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
  Widget build(BuildContext context) => DermairePage(
    showBack: false,
    centered: true,
    eyebrow: 'You’re ready',
    title: 'Account created',
    subtitle: 'Your private skin lab is ready for its first experiment.',
    children: [
      const SizedBox(height: 24),
      Center(
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: DermaireColors.safeBackground,
            border: Border.all(color: DermaireColors.safe, width: 2),
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 58,
            color: DermaireColors.safe,
          ),
        ),
      ),
      const SizedBox(height: 36),
      FilledButton(
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SkinProfileScreen(state: state)),
        ),
        child: const Text('Start my skin experiment'),
      ),
    ],
  );
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
  Map<String, dynamic>? profile;
  final draft = <String, dynamic>{};
  final contextDraft = <String, dynamic>{};
  String? error;
  bool saving = false;
  int section = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      error = null;
    });
    try {
      final result = await ApiService.instance.getCurrentUser();
      if (result == null) throw Exception('Profile unavailable');
      if (mounted) {
        setState(() {
          profile = result;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not load your profile. Retry before editing.';
        });
      }
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
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await ApiService.instance.updateSkinProfile(
        fields: {
          ...draft,
          if (contextDraft.isNotEmpty) 'profile_context': contextDraft,
        },
      );
      if (!mounted) return;
      widget.state.skinConcerns
        ..clear()
        ..addAll((result['skin_concerns'] as List).cast<String>());
      widget.state.selectGoal(result['selected_goal'] as String? ?? '');
      if (widget.editing) {
        Navigator.of(context).pop();
      } else {
        _openApp(context, widget.state);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'Save was not confirmed. Your draft is still here. Please retry.';
        });
      }
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
      if (error != null) Text(error!, key: const Key('profileError')),
      if (profile == null) ...[
        if (error == null)
          const Center(child: CircularProgressIndicator())
        else
          TextButton(onPressed: load, child: const Text('Retry')),
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
          onPressed: saving ? null : save,
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
