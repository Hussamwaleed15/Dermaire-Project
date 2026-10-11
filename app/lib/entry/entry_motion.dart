import 'package:flutter/material.dart';

abstract final class EntryMotion {
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  static Duration duration(BuildContext context, int milliseconds) =>
      reduced(context) ? Duration.zero : Duration(milliseconds: milliseconds);
}

/// Entry routes only; immediate session invalidation stays immediate in main.
PageRoute<T> entryRoute<T>(BuildContext context, Widget page) {
  final reduced = EntryMotion.reduced(context);
  return PageRouteBuilder<T>(
    transitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 240),
    reverseTransitionDuration: reduced
        ? Duration.zero
        : const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) => reduced
        ? child
        : FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .015), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          ),
  );
}

Future<T?> openEntry<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(entryRoute<T>(context, page));

class EntryReveal extends StatelessWidget {
  const EntryReveal({super.key, required this.child, this.success = false});
  final Widget child;
  final bool success;
  @override
  Widget build(BuildContext context) => EntryMotion.reduced(context)
      ? child
      : TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: success ? 220 : 180),
          curve: Curves.easeOutCubic,
          child: child,
          builder: (_, value, child) => Opacity(
            opacity: value,
            child: success
                ? Transform.scale(scale: .96 + .04 * value, child: child)
                : child,
          ),
        );
}

/// Visual feedback does not submit; the button retains its native semantics.
class EntryPress extends StatefulWidget {
  const EntryPress({super.key, required this.child});
  final Widget child;
  @override
  State<EntryPress> createState() => _EntryPressState();
}

class _EntryPressState extends State<EntryPress> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => down = true),
    onPointerUp: (_) => setState(() => down = false),
    onPointerCancel: (_) => setState(() => down = false),
    child: AnimatedScale(
      scale: down && !EntryMotion.reduced(context) ? .985 : 1,
      duration: EntryMotion.duration(context, 100),
      child: widget.child,
    ),
  );
}
