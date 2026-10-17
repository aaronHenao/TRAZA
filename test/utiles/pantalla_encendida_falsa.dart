import 'package:traza/services/pantalla_encendida_provider.dart';

/// Anota cada vez que la app pide mantener la pantalla encendida o dejarla
/// apagarse, sin tocar el plugin.
class PantallaEncendidaFalsa implements PantallaEncendida {
  /// Cada petición, en orden: `true` = no apagar, `false` = puede apagarse.
  final List<bool> peticiones = [];

  /// Lo último que se pidió; `false` si no se pidió nada.
  bool get encendida => peticiones.isNotEmpty && peticiones.last;

  @override
  Future<void> mantener({required bool encendida}) async {
    peticiones.add(encendida);
  }
}
