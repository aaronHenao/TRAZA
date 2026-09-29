import 'package:traza/models/experiencia_ganada.dart';
import 'package:traza/services/experiencia_service.dart';

/// Experiencia en memoria: responde lo que la prueba le indique y cuenta
/// cuántas veces se le pidió la acumulada.
class ExperienciaFalsa implements ExperienciaRepository {
  ExperienciaFalsa({
    this.acumulada = 0,
    Map<String, ExperienciaDeEntrenamiento>? porEntrenamiento,
  }) : porEntrenamiento = porEntrenamiento ?? {};

  int acumulada;

  /// Lo que devuelve `ganadaEn` para cada entrenamiento. Sin entrada, null:
  /// el entrenamiento no se procesó.
  final Map<String, ExperienciaDeEntrenamiento> porEntrenamiento;

  /// Si no es null, las lecturas lo lanzan.
  Object? error;

  var consultas = 0;

  @override
  Future<int> experienciaAcumulada() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return acumulada;
  }

  @override
  Future<ExperienciaDeEntrenamiento?> ganadaEn(String entrenamientoId) async {
    final error = this.error;
    if (error != null) throw error;
    return porEntrenamiento[entrenamientoId];
  }
}
