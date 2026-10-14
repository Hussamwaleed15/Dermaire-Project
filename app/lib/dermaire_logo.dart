import 'package:flutter/material.dart';

/// Original supplied artwork, selected automatically by the active app theme.
class DermaireLogo extends StatelessWidget {
  const DermaireLogo({
    super.key,
    required this.size,
    this.semanticLabel = 'Dermaire logo',
    this.excludeFromSemantics = false,
  });
  static const lightAsset = 'assets/images/dermaire-logo-light.png';
  static const darkAsset = 'assets/images/dermaire-logo-dark.png';
  final double size;
  final String semanticLabel;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) => Image.asset(
    Theme.of(context).brightness == Brightness.dark ? darkAsset : lightAsset,
    width: size,
    height: size,
    fit: BoxFit.contain,
    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
    semanticLabel: semanticLabel,
    excludeFromSemantics: excludeFromSemantics,
  );
}
