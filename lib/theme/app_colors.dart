import 'package:flutter/material.dart';

/// Paleta de TRAZA.
///
/// Los valores replican una a una las variables CSS del prototipo
/// (`docs/prototipo.html`) para que el diseño y la app no se desalineen.
abstract final class AppColors {
  static const primary = Color(0xFF613DC1);
  static const primaryDark = Color(0xFF4C2F9C);
  static const primaryTint = Color(0xFFEFEAFC);

  static const secondary = Color(0xFF858AE3);
  static const secondaryDark = Color(0xFF5B60B0);
  static const secondaryTint = Color(0xFFEFF0FB);

  static const accent = Color(0xFFD7F204);
  static const accentInk = Color(0xFF57611A);
  static const accentTint = Color(0xFFF8FCDA);

  static const danger = Color(0xFFE5484D);
  static const dangerTint = Color(0xFFFDECEC);

  static const bg = Color(0xFFFFFFFF);
  static const bgAlt = Color(0xFFF6F6F9);
  static const line = Color(0xFFEAEAF0);

  static const ink = Color(0xFF0D0D0D);
  static const ink2 = Color(0xFF6B6B70);
  static const ink3 = Color(0xFFA3A3A8);
}
