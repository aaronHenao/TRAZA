import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Tema de TRAZA, derivado del prototipo (`docs/prototipo.html`).
///
/// La tipografía es Inter en los pesos 400–800 que usa el prototipo.
abstract final class AppTheme {
  static ThemeData get light {
    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryTint,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryTint,
        onSecondaryContainer: AppColors.secondaryDark,
        error: AppColors.danger,
        onError: Colors.white,
        errorContainer: AppColors.dangerTint,
        surface: AppColors.bg,
        onSurface: AppColors.ink,
        surfaceContainerHighest: AppColors.bgAlt,
        onSurfaceVariant: AppColors.ink2,
        outline: AppColors.line,
        outlineVariant: AppColors.line,
      ),
      textTheme: textTheme,

      // `.btn.btn-primary` del prototipo: pill, 14.5px, peso 700.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.ink3,
          disabledForegroundColor: Colors.white,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700),
          shape: const StadiumBorder(),
        ),
      ),

      // `.btn.btn-outline`.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.ink,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700),
          side: const BorderSide(color: AppColors.line, width: 1.5),
          shape: const StadiumBorder(),
        ),
      ),

      // `.field input`.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg,
        hintStyle: GoogleFonts.inter(fontSize: 14.5, color: AppColors.ink3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: _inputBorder(AppColors.line),
        enabledBorder: _inputBorder(AppColors.line),
        focusedBorder: _inputBorder(AppColors.primary),
        errorBorder: _inputBorder(AppColors.danger),
        focusedErrorBorder: _inputBorder(AppColors.danger),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide(color: color, width: 1.5),
  );
}
