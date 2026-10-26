import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/tipo_objetivo.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/services/historial_service.dart';
import 'package:traza/services/objetivos_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/widgets/indicadores_semana.dart';

import '../utiles/retos_repository_falso.dart';

/// Historial de mentira: responde lo que la prueba le indique.
class _HistorialFalso implements HistorialRepository {
  _HistorialFalso(this.respuesta);

  Future<List<ResumenEntrenamiento>> Function() respuesta;

  @override
  Future<List<ResumenEntrenamiento>> cargar() => respuesta();
}

/// Objetivos de mentira: solo se le pregunta por la meta de distancia.
class _ObjetivosFalsos implements ObjetivosRepository {
  _ObjetivosFalsos(this.respuesta);

  Future<Map<TipoObjetivo, num>> Function() respuesta;

  @override
  Future<Map<TipoObjetivo, num>> cargar() => respuesta();

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {}
}

/// Retos de mentira: devuelve los que el corredor tendría activados.
class _RetosFalsos extends RetosRepositorioFalso {
  _RetosFalsos(this.respuesta);

  Future<List<RetoDelUsuario>> Function() respuesta;

  @override
  Future<List<RetoDelUsuario>> misRetos() => respuesta();
}

/// Pruebas de los tres indicadores de la semana (SCRUM-287).
///
/// Es el criterio 2 de SCRUM-283: kilómetros, actividades y retos activos.
void main() {
  // Miércoles: la semana empezó el lunes 14.
  final ahora = DateTime(2026, 9, 16, 10);

  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');

  Reto reto(String id) => Reto(
    id: id,
    nombre: 'Reto $id',
    descripcion: 'Qué hay que hacer en el reto $id.',
    periodicidad: PeriodicidadReto.semanal,
    metaKm: 20,
    xpOtorgada: 100,
    vigencia: VigenciaReto(
      inicio: DateTime(2026, 9, 14),
      fin: DateTime(2026, 9, 20),
    ),
    estado: EstadoReto.activo,
    tipoActividad: correr,
  );

  RetoDelUsuario enCurso(String id) => RetoDelUsuario(
    reto: reto(id),
    estado: EstadoRetoUsuario.enProgreso,
    progresoKm: 4,
    fechaActivacion: DateTime(2026, 9, 14, 8),
  );

  RetoDelUsuario completado(String id) => RetoDelUsuario(
    reto: reto(id),
    estado: EstadoRetoUsuario.completado,
    progresoKm: 20,
    fechaActivacion: DateTime(2026, 9, 14, 8),
    fechaCompletado: DateTime(2026, 9, 15, 9),
  );

  final entrenamientos = [
    ResumenEntrenamiento(
      entrenamientoId: 'e1',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 16, 7),
      duracion: const Duration(minutes: 30),
      distanciaMetros: 5100,
    ),
    ResumenEntrenamiento(
      entrenamientoId: 'e2',
      nombreActividad: 'Caminar',
      fechaFin: DateTime(2026, 9, 15, 18),
      duracion: const Duration(minutes: 40),
      distanciaMetros: 3000,
    ),
    // De la semana pasada: no cuenta en ninguno de los indicadores.
    ResumenEntrenamiento(
      entrenamientoId: 'e3',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 11, 18),
      duracion: const Duration(minutes: 50),
      distanciaMetros: 9000,
    ),
  ];

  String valorDe(WidgetTester tester, Key clave) =>
      tester.widget<Text>(find.byKey(clave)).data!;

  Future<void> montar(
    WidgetTester tester, {
    Future<List<ResumenEntrenamiento>> Function()? historial,
    Future<Map<TipoObjetivo, num>> Function()? objetivos,
    Future<List<RetoDelUsuario>> Function()? retos,
    bool esperar = true,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialRepositoryProvider.overrideWithValue(
            _HistorialFalso(historial ?? () async => entrenamientos),
          ),
          objetivosRepositoryProvider.overrideWithValue(
            _ObjetivosFalsos(
              objetivos ?? () async => {TipoObjetivo.distancia: 15},
            ),
          ),
          retosRepositoryProvider.overrideWithValue(
            _RetosFalsos(retos ?? () async => [enCurso('r1')]),
          ),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: IndicadoresSemana(),
            ),
          ),
        ),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('las tres cifras', () {
    testWidgets('kilómetros de la semana, actividades y retos activos', (
      tester,
    ) async {
      await montar(tester, retos: () async => [enCurso('r1'), enCurso('r2')]);

      expect(find.text('ESTA SEMANA'), findsOneWidget);
      // 5.1 + 3.0 desde el lunes, contra la meta de 15 del perfil.
      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '8.1 / 15');
      expect(valorDe(tester, IndicadoresSemana.claveActividades), '2');
      expect(valorDe(tester, IndicadoresSemana.claveRetos), '2');
      expect(find.text('km'), findsOneWidget);
      expect(find.text('actividades'), findsOneWidget);
      expect(find.text('retos activos'), findsOneWidget);
    });

    testWidgets('sin meta configurada los kilómetros van solos', (
      tester,
    ) async {
      await montar(tester, objetivos: () async => {});

      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '8.1');
      expect(
        find.text(
          'Ponte una meta de distancia en tu perfil para seguirla desde aquí.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('con meta, no se repite la invitación a ponerse una', (
      tester,
    ) async {
      await montar(tester);

      expect(find.textContaining('Ponte una meta de distancia'), findsNothing);
    });

    testWidgets('una sola actividad y un solo reto van en singular', (
      tester,
    ) async {
      await montar(
        tester,
        historial: () async => [entrenamientos.first],
        retos: () async => [enCurso('r1')],
      );

      expect(valorDe(tester, IndicadoresSemana.claveActividades), '1');
      expect(find.text('actividad'), findsOneWidget);
      expect(find.text('reto activo'), findsOneWidget);
    });

    testWidgets('sin nada esta semana muestra ceros, no un hueco', (
      tester,
    ) async {
      await montar(
        tester,
        historial: () async => [],
        retos: () async => const [],
      );

      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '0.0 / 15');
      expect(valorDe(tester, IndicadoresSemana.claveActividades), '0');
      expect(valorDe(tester, IndicadoresSemana.claveRetos), '0');
    });
  });

  group('qué cuenta como reto activo', () {
    testWidgets('los completados no cuentan', (tester) async {
      await montar(
        tester,
        retos: () async => [enCurso('r1'), completado('r2')],
      );

      expect(valorDe(tester, IndicadoresSemana.claveRetos), '1');
    });

    testWidgets('los vencidos tampoco', (tester) async {
      // Su vigencia terminó antes de hoy: ya no se puede cumplir.
      final vencido = RetoDelUsuario(
        reto: Reto(
          id: 'r9',
          nombre: 'Reto de la semana pasada',
          descripcion: 'Ya se acabó.',
          periodicidad: PeriodicidadReto.semanal,
          metaKm: 20,
          xpOtorgada: 100,
          vigencia: VigenciaReto(
            inicio: DateTime(2026, 9, 7),
            fin: DateTime(2026, 9, 13),
          ),
          estado: EstadoReto.activo,
          tipoActividad: correr,
        ),
        estado: EstadoRetoUsuario.enProgreso,
        progresoKm: 2,
        fechaActivacion: DateTime(2026, 9, 7, 8),
      );

      await montar(tester, retos: () async => [enCurso('r1'), vencido]);

      expect(valorDe(tester, IndicadoresSemana.claveRetos), '1');
    });
  });

  group('cuando algo no se puede consultar', () {
    testWidgets('si fallan los retos, las otras dos cifras siguen', (
      tester,
    ) async {
      await montar(tester, retos: () async => throw Exception('sin red'));

      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '8.1 / 15');
      expect(valorDe(tester, IndicadoresSemana.claveActividades), '2');
      // La caja de retos queda en guion, no en cero: cero sería mentira.
      expect(valorDe(tester, IndicadoresSemana.claveRetos), '—');
    });

    testWidgets('si fallan los objetivos, los kilómetros siguen', (
      tester,
    ) async {
      await montar(tester, objetivos: () async => throw Exception('sin red'));

      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '8.1');
    });

    testWidgets('mientras carga la semana lo dice, y si falla también', (
      tester,
    ) async {
      final pendiente = Completer<List<ResumenEntrenamiento>>();
      await montar(tester, historial: () => pendiente.future, esperar: false);

      expect(find.text('Cargando tu semana…'), findsOneWidget);

      pendiente.completeError(Exception('sin red'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No pudimos cargar tu semana'),
        findsOneWidget,
      );
    });
  });

  testWidgets('las tres cajas caben en la pantalla más estrecha', (
    tester,
  ) async {
    await montar(tester, tamano: const Size(320, 568));

    expect(tester.takeException(), isNull);
    expect(valorDe(tester, IndicadoresSemana.claveKilometros), '8.1 / 15');
    expect(valorDe(tester, IndicadoresSemana.claveRetos), '1');
  });
}
