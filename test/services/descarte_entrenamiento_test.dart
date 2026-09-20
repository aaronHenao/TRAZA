import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/services/actividad_provider.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/entrenamiento_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/tipos_actividad_service.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/reloj_falso.dart';

/// Pruebas del descarte del entrenamiento (SCRUM-96): la fila queda
/// `cancelado` aunque la red falle en el momento de descartar.
void main() {
  late _EntrenamientosFalso repositorio;
  late FuenteUbicacionFalsa gps;
  late RelojFalso reloj;
  late ProviderContainer container;

  setUp(() {
    repositorio = _EntrenamientosFalso();
    gps = FuenteUbicacionFalsa();
    reloj = RelojFalso();
    addTearDown(() => gps.cerrar());

    container = ProviderContainer(
      overrides: [
        entrenamientoRepositoryProvider.overrideWithValue(repositorio),
        // Sin esperas de verdad entre reintentos.
        esperaEntreIntentosProvider.overrideWithValue(Duration.zero),
        fuenteUbicacionProvider.overrideWithValue(gps),
        relojProvider.overrideWithValue(reloj.call),
        tiposActividadRepositoryProvider.overrideWithValue(
          const _CatalogoFalso(),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  /// Arranca un entrenamiento, como hace la pantalla de inicio.
  Future<String> iniciar() async {
    await container.read(tiposActividadProvider.future);
    final error = await container.read(inicioEntrenamientoProvider).iniciar();
    expect(error, isNull);
    return container.read(entrenamientoActualProvider)!;
  }

  Future<void> descartar() =>
      container.read(descarteEntrenamientoProvider).descartar();

  List<DescartePendiente> pendientes() =>
      container.read(descartesPendientesProvider);

  test('descartar deja la fila cancelada y suelta la actividad', () async {
    final id = await iniciar();
    container.read(actividadIniciadaProvider.notifier).marcarIniciada();

    await descartar();

    expect(repositorio.cancelados, [id]);
    expect(container.read(entrenamientoActualProvider), isNull);
    expect(container.read(actividadIniciadaProvider), isFalse);
    expect(pendientes(), isEmpty);
  });

  test('un corte de red puntual se resuelve reintentando', () async {
    await iniciar();
    // Falla las dos primeras veces y responde a la tercera.
    repositorio.fallosSeguidos = 2;

    await descartar();

    expect(repositorio.intentos, 3);
    expect(repositorio.cancelados, hasLength(1));
    expect(pendientes(), isEmpty, reason: 'no queda nada por reintentar');
  });

  test('la hora del descarte es la de cuando el usuario descartó, no la del '
      'intento que funcionó', () async {
    await iniciar();
    final cuandoDescarto = reloj();
    repositorio.fallosSeguidos = 2;

    await descartar();

    expect(repositorio.fechasFin.single, cuandoDescarto);
  });

  test('si no hay red en ningún intento, queda pendiente', () async {
    final id = await iniciar();
    repositorio.fallosSeguidos = 99;

    await descartar();

    expect(repositorio.cancelados, isEmpty);
    expect(pendientes().single.entrenamientoId, id);
    // La actividad se soltó igual: el usuario ya descartó.
    expect(container.read(entrenamientoActualProvider), isNull);
    expect(container.read(actividadIniciadaProvider), isFalse);
  });

  test('el siguiente entrenamiento cierra lo que quedó pendiente', () async {
    final descartado = await iniciar();
    repositorio.fallosSeguidos = 99;
    await descartar();
    expect(pendientes(), hasLength(1));

    // Con red de nuevo, el usuario empieza otro entrenamiento.
    repositorio.fallosSeguidos = 0;
    await container.read(inicioEntrenamientoProvider).iniciar();
    await pumpEventQueue();

    expect(repositorio.cancelados, [descartado]);
    expect(pendientes(), isEmpty);
  });

  test('si el entrenamiento ya no está en curso, deja de reintentarlo',
      () async {
    await iniciar();
    // Alguien lo cerró antes: no hay nada que cancelar.
    repositorio.noEncontrado = true;

    await descartar();

    expect(repositorio.intentos, 1, reason: 'no tiene sentido insistir');
    expect(pendientes(), isEmpty);
  });

  test('dos descartes fallidos no se duplican en la lista de pendientes',
      () async {
    await iniciar();
    repositorio.fallosSeguidos = 99;
    await descartar();
    final id = pendientes().single.entrenamientoId;

    // Reintentar otra vez sin red lo deja igual, no lo duplica.
    await container.read(descarteEntrenamientoProvider).reintentarPendientes();

    expect(pendientes(), hasLength(1));
    expect(pendientes().single.entrenamientoId, id);
  });
}

/// Entrenamientos en memoria que puede fallar las veces que la prueba diga.
class _EntrenamientosFalso implements EntrenamientoRepository {
  final creados = <String>[];
  final cancelados = <String>[];
  final fechasFin = <DateTime>[];

  /// Cuántas llamadas seguidas a `cancelar` fallan antes de funcionar.
  int fallosSeguidos = 0;

  /// `cancelar` responde que el entrenamiento ya no está en curso.
  bool noEncontrado = false;

  /// Llamadas a `cancelar`, incluidas las que fallaron.
  int intentos = 0;

  @override
  Future<String> crear({required String tipoActividadId}) async {
    creados.add(tipoActividadId);
    return 'entrenamiento-${creados.length}';
  }

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) async {
    intentos++;
    if (noEncontrado) {
      throw EntrenamientoNoEncontradoException(entrenamientoId);
    }
    if (fallosSeguidos > 0) {
      fallosSeguidos--;
      throw StateError('sin red');
    }
    cancelados.add(entrenamientoId);
    fechasFin.add(fechaFin);
  }

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) => throw UnimplementedError('El descarte no cierra entrenamientos');

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError('El descarte no lee entrenamientos');
}

class _CatalogoFalso implements TiposActividadRepository {
  const _CatalogoFalso();

  @override
  Future<List<TipoActividad>> cargar() async => const [
    TipoActividad(id: 'id-correr', nombre: 'Correr'),
  ];
}
