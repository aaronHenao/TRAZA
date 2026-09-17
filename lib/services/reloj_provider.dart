import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firma del reloj del sistema. Se inyecta para poder controlar el
/// tiempo desde las pruebas.
typedef Reloj = DateTime Function();

/// Reloj del sistema. Las pruebas lo sobrescriben para avanzar el
/// tiempo a voluntad.
final relojProvider = Provider<Reloj>((ref) => DateTime.now);
