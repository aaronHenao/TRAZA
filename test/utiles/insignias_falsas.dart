import 'package:traza/models/insignia.dart';
import 'package:traza/services/insignias_service.dart';

/// Catálogo de insignias en memoria (SCRUM-193): responde lo que la prueba le
/// indique y cuenta cuántas veces se le pidió.
class InsigniasFalsas implements InsigniasRepository {
  InsigniasFalsas({this.catalogo = const []});

  /// Lo que devolvería la base: de menor a mayor XP requerida, con las que el
  /// usuario ya obtuvo marcadas.
  List<Insignia> catalogo;

  /// Si no es null, `listar` lo lanza.
  Object? error;

  var consultas = 0;

  @override
  Future<List<Insignia>> listar() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return catalogo;
  }
}
