import 'package:flutter/material.dart';
import '../dermaire_theme.dart';
import 'entry_copy.dart';
import 'entry_motion.dart';

class EntryPage extends StatelessWidget {
  const EntryPage({
    super.key,
    required this.children,
    this.footer = const [],
    this.title,
    this.subtitle,
    this.eyebrow,
    this.showBack = true,
    this.headerActions = const [],
    this.controller,
    this.scrollKey,
    this.editorial = false,
  });
  final List<Widget> children, footer, headerActions;
  final String? title, subtitle, eyebrow;
  final bool showBack, editorial;
  final ScrollController? controller;
  final Key? scrollKey;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).brightness == Brightness.dark
        ? DermaireTheme.dark
        : DermaireTheme.light;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final t = EntryTokens.of(context);
          final content = <Widget>[
            if (eyebrow != null)
              Text(
                eyebrow!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.secondary,
                ),
              ),
            if (title != null) ...[
              const SizedBox(height: 8),
              Text(
                title!,
                style: TextStyle(
                  fontFamily: editorial ? 'Fraunces' : 'Karla',
                  fontSize: editorial ? 38 : 28,
                  fontWeight: FontWeight.w600,
                  height: 1.12,
                ),
              ),
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 10),
              Text(
                subtitle!,
                style: TextStyle(color: t.secondary, height: 1.45),
              ),
            ],
            const SizedBox(height: 24),
            ...children,
          ];
          final actions = Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: footer
                  .map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: w,
                    ),
                  )
                  .toList(),
            ),
          );
          return Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // At large text or with the keyboard, actions join the scroll so every
                  // control remains reachable without shrinking type or clipping terms.
                  final compact =
                      constraints.maxHeight < 560 ||
                      MediaQuery.textScalerOf(context).scale(14) > 21;
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  if (showBack &&
                                      Navigator.of(context).canPop())
                                    IconButton(
                                      tooltip: MaterialLocalizations.of(
                                        context,
                                      ).backButtonTooltip,
                                      onPressed: () =>
                                          Navigator.of(context).maybePop(),
                                      icon: const Icon(Icons.arrow_back),
                                    ),
                                  Image.asset(
                                    'assets/images/dermaire-logo.webp',
                                    width: 42,
                                    height: 42,
                                    excludeFromSemantics: true,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'Dermaire',
                                      style: TextStyle(
                                        fontFamily: 'Fraunces',
                                        fontSize: 24,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  ...headerActions,
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                key: scrollKey,
                                controller: controller,
                                padding: const EdgeInsets.only(
                                  top: 12,
                                  bottom: 20,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [...content, if (compact) actions],
                                ),
                              ),
                            ),
                            if (!compact && footer.isNotEmpty) actions,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final t = EntryTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.card,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

class EntryStatusPage extends StatelessWidget {
  const EntryStatusPage({
    super.key,
    required this.message,
    required this.onSignOut,
    this.error,
    this.onRetry,
    this.retryKey,
    this.success = false,
    this.onContinue,
    this.continueKey,
  });
  final String message;
  final String? error;
  final VoidCallback? onSignOut, onRetry, onContinue;
  final Key? retryKey, continueKey;
  final bool success;
  @override
  Widget build(BuildContext context) {
    final c = EntryCopy.of(context);
    return EntryPage(
      showBack: false,
      footer: [
        if (onContinue != null)
          EntryPress(
            child: FilledButton(
              key: continueKey,
              onPressed: onContinue,
              child: Text(c.continueApp),
            ),
          ),
        if (onRetry != null)
          EntryPress(
            child: FilledButton(
              key: retryKey,
              onPressed: onRetry,
              child: Text(c.retry),
            ),
          ),
        if (onSignOut != null)
          TextButton(
            key: const Key('consentSignOut'),
            onPressed: onSignOut,
            child: Text(c.signOut),
          ),
      ],
      children: [
        EntryReveal(
          success: success,
          child: Builder(
            builder: (context) {
              final t = EntryTokens.of(context);
              return Column(
                children: [
                  const SizedBox(height: 48),
                  if (success || error != null)
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: t.card,
                        border: Border.all(
                          color: error != null
                              ? Theme.of(context).colorScheme.error
                              : t.action,
                        ),
                      ),
                      child: Icon(
                        error != null
                            ? Icons.error_outline
                            : Icons.check_rounded,
                        size: 48,
                        color: error != null
                            ? Theme.of(context).colorScheme.error
                            : t.action,
                      ),
                    )
                  else
                    Image.asset(
                      'assets/images/dermaire-logo.webp',
                      width: 96,
                      height: 96,
                      semanticLabel: 'Dermaire',
                    ),
                  const SizedBox(height: 28),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      error != null ? c.failure : message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        height: 1.18,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (error != null)
                    Text(
                      c.error(error!),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.secondary),
                    )
                  else if (success) ...[
                    EntryCard(
                      child: Column(
                        children: [
                          Text(
                            c.choose(
                              'Safety acceptance confirmed by the server',
                              'تم تأكيد موافقة السلامة من السيرفر',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            c.choose(
                              'Account profile loaded',
                              'تم تحميل ملف الحساب',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      c.clinicalDisclaimer,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.secondary),
                    ),
                  ] else
                    Semantics(
                      label: message,
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: EntryMotion.reduced(context)
                            ? Icon(Icons.hourglass_empty, color: t.action)
                            : CircularProgressIndicator(
                                color: t.action,
                                strokeWidth: 2,
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Stable visible labels; focused border feedback follows the entry motion
/// policy. Native text input, validation, autofill and semantics stay intact.
class EntryField extends StatefulWidget {
  const EntryField({super.key, required this.child});
  final Widget child;
  @override
  State<EntryField> createState() => _EntryFieldState();
}

class _EntryFieldState extends State<EntryField> {
  bool focused = false;
  @override
  Widget build(BuildContext context) {
    final t = EntryTokens.of(context);
    final decoration = Theme.of(context).inputDecorationTheme.copyWith(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    );
    return Focus(
      canRequestFocus: false,
      onFocusChange: (value) => setState(() => focused = value),
      child: AnimatedContainer(
        duration: EntryMotion.duration(context, 140),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: focused ? t.action : t.border, width: 1.5),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(inputDecorationTheme: decoration),
          child: widget.child,
        ),
      ),
    );
  }
}
