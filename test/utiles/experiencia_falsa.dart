import 'package:traza/services/experiencia_service.dart';

/// Experiencia acumulada en memoria: responde lo que la prueba le indique y
/// cuenta cuántas veces se la pidieron.
class ExperienciaFalsa implements ExperienciaRepository {
  ExperienciaFalsa({this.acumulada = 0});

  int acumulada;

  /// Si no es null, la lectura lo lanza.
  Object? error;

  var consultas = 0;

  @override
  Future<int> experienciaAcumulada() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return acumulada;
  }
}
