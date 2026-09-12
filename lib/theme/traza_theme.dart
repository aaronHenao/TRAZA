import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta y tokens de diseño de TRAZA, tomados del prototipo
/// (`contexto_proyecto/prototipos/screens_sprint1.html`).
class TrazaColors {
  const TrazaColors._();

  static const Color primary = Color(0xFF613DC1);
  static const Color primaryDark = Color(0xFF4C2F9C);
  static const Color primaryTint = Color(0xFFEFEAFC);

  static const Color secondary = Color(0xFF858AE3);
  static const Color secondaryDark = Color(0xFF5B60B0);
  static const Color secondaryTint = Color(0xFFEFF0FB);

  static const Color accent = Color(0xFFD7F204);
  static const Color accentInk = Color(0xFF57611A);

  static const Color danger = Color(0xFFE5484D);

  static const Color bg = Color(0xFFFFFFFF);
  static const Color bgAlt = Color(0xFFF6F6F9);
  static const Color line = Color(0xFFEAEAF0);

  static const Color ink = Color(0xFF0D0D0D);
  static const Color ink2 = Color(0xFF6B6B70);
  static const Color ink3 = Color(0xFFA3A3A8);

  /// Fondo oscuro de la pantalla de entrenamiento en curso.
  static const Color trackingTop = Color(0xFF18142B);
  static const Color trackingBottom = Color(0xFF241D3D);
}

/// Radios del prototipo (`--radius-lg`, `--radius-md`, `--radius-sm`).
class TrazaRadius {
  const TrazaRadius._();

  static const double lg = 20;
  static const double md = 14;
  static const double sm = 10;
}

/// Degradado del fondo de `#screen-tracking`: `linear-gradient(160deg, ...)`.
const LinearGradient trazaTrackingGradient = LinearGradient(
  begin: Alignment(-0.64, -1),
  end: Alignment(0.64, 1),
  colors: [TrazaColors.trackingTop, TrazaColors.trackingBottom],
);

/// Tema claro de la app. La tipografía del prototipo es Inter.
ThemeData buildTrazaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: TrazaColors.primary,
      primary: TrazaColors.primary,
      secondary: TrazaColors.secondary,
      error: TrazaColors.danger,
      surface: TrazaColors.bg,
    ),
    scaffoldBackgroundColor: TrazaColors.bg,
  );

  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: TrazaColors.ink,
      displayColor: TrazaColors.ink,
    ),
  );
}
