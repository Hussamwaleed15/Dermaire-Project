import 'package:flutter/material.dart';

abstract final class DermaireColors {
  static const background = Color(0xFFFAF4EC);
  static const caramel = Color(0xFFD8ACA6);
  static const deep = Color(0xFF681B22);
  static const ink = Color(0xFF2E2220);
  static const card = Color(0xFFFFFCF8);
  static const paper = Color(0xFFFAF4EC);
  static const line = Color(0x242E2220);
  static const safe = Color(0xFF6E8F6C);
  static const conflict = Color(0xFFB0503A);
  static const unknown = Color(0xFFC69A45);
  static const safeBackground = Color(0xFFEAF0E6);
  static const conflictBackground = Color(0xFFF6E3DD);
  static const unknownBackground = Color(0xFFF5EBD6);
  static const darkBackground = Color(0xFF17191E);
  static const darkSurface = Color(0xFF24272D);
  static const darkPaper = Color(0xFF2F333B);
  static const darkInk = Color(0xFFF7F7F9);
}

/// Semantic brand roles. Clinical status colors remain separate.
@immutable
class EntryTokens extends ThemeExtension<EntryTokens> {
  const EntryTokens({
    required this.canvas,
    required this.card,
    required this.raised,
    required this.ink,
    required this.secondary,
    required this.action,
    required this.pressed,
    required this.onAction,
    required this.border,
  });
  final Color canvas,
      card,
      raised,
      ink,
      secondary,
      action,
      pressed,
      onAction,
      border;
  static const light = EntryTokens(
    canvas: Color(0xFFFAF4EC),
    card: Color(0xFFFFFCF8),
    raised: Color(0xFFFFFCF8),
    ink: Color(0xFF2E2220),
    secondary: Color(0xFF685853),
    action: Color(0xFF681B22),
    pressed: Color(0xFF481116),
    onAction: Color(0xFFFFFCF8),
    border: Color(0xFFD8ACA6),
  );
  static const dark = EntryTokens(
    canvas: Color(0xFF17191E),
    card: Color(0xFF24272D),
    raised: Color(0xFF2F333B),
    ink: Color(0xFFF7F7F9),
    secondary: Color(0xFFBEC1C9),
    action: Color(0xFFE8A1B6),
    pressed: Color(0xFFD4869F),
    onAction: Color(0xFF17191E),
    border: Color(0xFF3B3F47),
  );
  static EntryTokens of(BuildContext context) =>
      Theme.of(context).extension<EntryTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  @override
  EntryTokens copyWith({
    Color? canvas,
    Color? card,
    Color? raised,
    Color? ink,
    Color? secondary,
    Color? action,
    Color? pressed,
    Color? onAction,
    Color? border,
  }) => EntryTokens(
    canvas: canvas ?? this.canvas,
    card: card ?? this.card,
    raised: raised ?? this.raised,
    ink: ink ?? this.ink,
    secondary: secondary ?? this.secondary,
    action: action ?? this.action,
    pressed: pressed ?? this.pressed,
    onAction: onAction ?? this.onAction,
    border: border ?? this.border,
  );
  @override
  EntryTokens lerp(covariant EntryTokens? other, double t) => other == null
      ? this
      : EntryTokens(
          canvas: Color.lerp(canvas, other.canvas, t)!,
          card: Color.lerp(card, other.card, t)!,
          raised: Color.lerp(raised, other.raised, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          secondary: Color.lerp(secondary, other.secondary, t)!,
          action: Color.lerp(action, other.action, t)!,
          pressed: Color.lerp(pressed, other.pressed, t)!,
          onAction: Color.lerp(onAction, other.onAction, t)!,
          border: Color.lerp(border, other.border, t)!,
        );
}

abstract final class DermaireTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final t = brightness == Brightness.dark
        ? EntryTokens.dark
        : EntryTokens.light;
    final body = TextStyle(
      fontFamily: 'Karla',
      fontFamilyFallback: const ['Noto Sans Arabic', 'Geeza Pro', 'SF Arabic'],
      color: t.ink,
      height: 1.35,
    );
    final display = body.copyWith(
      fontFamily: 'Fraunces',
      fontWeight: FontWeight.w600,
      height: 1.15,
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Karla',
      fontFamilyFallback: const ['Noto Sans Arabic', 'Geeza Pro', 'SF Arabic'],
      brightness: brightness,
      extensions: [t],
      scaffoldBackgroundColor: t.canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: t.action,
        brightness: brightness,
        primary: t.action,
        onPrimary: t.onAction,
        surface: t.card,
        onSurface: t.ink,
        onSurfaceVariant: t.secondary,
        outline: t.border,
        error: brightness == Brightness.dark
            ? const Color(0xFFFFB9B9)
            : const Color(0xFF92282D),
      ),
      textTheme: TextTheme(
        displayLarge: display,
        displayMedium: display,
        headlineLarge: display,
        headlineMedium: display,
        headlineSmall: display,
        titleLarge: display,
        titleMedium: body,
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: body,
        labelLarge: body,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: t.canvas,
        foregroundColor: t.ink,
        titleTextStyle: display.copyWith(fontSize: 20),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: t.onAction,
              textStyle: const TextStyle(
                fontFamily: 'Karla',
                fontFamilyFallback: [
                  'Noto Sans Arabic',
                  'Geeza Pro',
                  'SF Arabic',
                ],
                fontWeight: FontWeight.w700,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? t.ink.withValues(alpha: .12)
                    : states.contains(WidgetState.pressed)
                    ? t.pressed
                    : t.action,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: t.ink,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          side: BorderSide(color: t.border),
          textStyle: const TextStyle(
            fontFamily: 'Karla',
            fontFamilyFallback: [
              'Noto Sans Arabic',
              'Geeza Pro',
              'SF Arabic',
            ],
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: t.action,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.card,
        labelStyle: TextStyle(color: t.secondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: border(t.border),
        enabledBorder: border(t.border),
        focusedBorder: border(t.action, 1.5),
      ),
      dividerColor: t.border,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.ink,
        contentTextStyle: TextStyle(
          fontFamily: 'Karla',
          fontFamilyFallback: const [
            'Noto Sans Arabic',
            'Geeza Pro',
            'SF Arabic',
          ],
          color: t.canvas,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
