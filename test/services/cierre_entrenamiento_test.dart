import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/recorrido.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/entrenamiento_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/progresion_provider.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';
import '../utiles/reloj_falso.dart';

/// Pruebas de la XP en el cierre del entrenamiento (SCRUM-206).
///
/// La XP la asigna el trigger de la base en el mismo cierre; lo que le toca a
/// la app es volver a leer la acumulada para que la progresión la refleje.
void main() {
  late _EntrenamientosFalso entrenamientos;
  late ExperienciaFalsa experiencia;
  late ProviderContainer container;

  setUp(() {
    entrenamientos = _EntrenamientosFalso();
    experiencia = ExperienciaFalsa(acumulada: 100);

    container = ProviderContainer(
      overrides: [
        entrenamientoActualProvider.overrideWithValue('e-1'),
        entrenamientoRepositoryProvider.overrideWithValue(entrenamientos),
        experienciaRepositoryProvider.overrideWithValue(experiencia),
        nivelesRepositoryProvider.overrideWithValue(
          NivelesFalso(
            catalogo: const [
              Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 120),
            ],
          ),
        ),
        relojProvider.overrideWithValue(RelojFalso().call),
      ],
    );
    addTearDown(container.dispose);
    // Como la pantalla de progresión abierta: la mantiene viva.
    container.listen(progresionProvider, (_, _) {});
  });

  Future<String?> finalizar() => container
      .read(cierreEntrenamientoProvider)
      .finalizar(
        duracion: const Duration(minutes: 30),
        recorrido: const Recorrido(),
        distanciaMetros: 5000,
      );

  test('al finalizar, la progresión vuelve a leer la XP', () async {
    final antes = await container.read(progresionProvider.future);
    expect(antes.nivelActual, isNull);

    // Lo que habría sumado el trigger al cerrar.
    experiencia.acumulada = 125;
    expect(await finalizar(), isNull);

    final despues = await container.read(progresionProvider.future);
    expect(despues.experiencia, 125);
    expect(despues.nivelActual?.nombre, 'Bronce');
    expect(experiencia.consultas, 2);
  });

  test('si el cierre no se guardó, no hay XP nueva que leer', () async {
    await container.read(progresionProvider.future);
    entrenamientos.fallar = true;

    expect(await finalizar(), isNotNull);

    await container.read(progresionProvider.future);
    expect(experiencia.consultas, 1);
  });
}

class _EntrenamientosFalso implements EntrenamientoRepository {
  bool fallar = false;

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) async {
    if (fallar) throw StateError('Supabase no disponible');
  }

  @override
  Future<String> crear({required String tipoActividadId}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) => throw UnimplementedError();

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError();
}
