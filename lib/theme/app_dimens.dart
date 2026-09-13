import 'package:flutter/material.dart';

/// Radios de borde del prototipo (`--radius-lg/md/sm`).
abstract final class AppRadius {
  static const lg = 20.0;
  static const md = 14.0;
  static const sm = 10.0;

  /// Los botones del prototipo usan `border-radius:100px`.
  static const pill = 100.0;
}

/// Espaciados recurrentes del prototipo.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

/// Sombra de las tarjetas (`--shadow`).
abstract final class AppShadow {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0A0D0D0D), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x120D0D0D), offset: Offset(0, 8), blurRadius: 24),
  ];
}
