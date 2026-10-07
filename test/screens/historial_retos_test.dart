import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/screens/retos/historial_retos_screen.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';

import '../utiles/retos_repository_falso.dart';

class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso(this.respuesta);

  Future<List<RetoDelUsuario>> Function() respuesta;
  var consultas = 0;

  @override
  Future<List<RetoDelUsuario>> misRetos() {
    consultas++;
    return respuesta();
  }
}

/// Pruebas del historial de retos: lo completado por fechas (SCRUM-174) y lo
/// vencido sin cumplir (SCRUM-173).
void main() {
  // Lunes 28 de septiembre de 2026.
  final ahora = DateTime(2026, 9, 28, 10);

  Reto reto({
    required String id,
    required String nombre,
    required DateTime fin,
    double metaKm = 15,
    int xp = 200,
  }) => Reto(
    id: id,
    nombre: nombre,
    descripcion: 'Qué hay que hacer.',
    periodicidad: PeriodicidadReto.semanal,
    metaKm: metaKm,
    xpOtorgada: xp,
    vigencia: VigenciaReto(inicio: DateTime(2026, 9, 21), fin: fin),
    estado: EstadoReto.activo,
    tipoActividad: const TipoActividad(id: 'tipo-correr', nombre: 'Correr'),
  );

  final enCurso = RetoDelUsuario(
    reto: reto(
      id: 'a',
      nombre: 'Camina 3 km esta semana',
      fin: DateTime(2026, 10, 4),
      metaKm: 3,
      xp: 30,
    ),
    estado: EstadoRetoUsuario.enProgreso,
    progresoKm: 1.2,
    fechaActivacion: DateTime(2026, 9, 28, 8),
  );
  final completadoHoy = RetoDelUsuario(
    reto: reto(id: 'b', nombre: 'Corre 15 km', fin: DateTime(2026, 10, 4)),
    estado: EstadoRetoUsuario.completado,
    progresoKm: 15,
    fechaActivacion: DateTime(2026, 9, 21, 8),
    fechaCompletado: DateTime(2026, 9, 28, 9),
  );
  final completadoAyer = RetoDelUsuario(
    reto: reto(id: 'c', nombre: 'Trote de 8 km', fin: DateTime(2026, 9, 27)),
    estado: EstadoRetoUsuario.completado,
    progresoKm: 8,
    fechaActivacion: DateTime(2026, 9, 21, 8),
    fechaCompletado: DateTime(2026, 9, 27, 18),
  );
  final vencido = RetoDelUsuario(
    reto: reto(
      id: 'd',
      nombre: 'Corre 1 km hoy',
      fin: DateTime(2026, 9, 24),
      metaKm: 1,
      xp: 10,
    ),
    estado: EstadoRetoUsuario.enProgreso,
    progresoKm: 1 / 3,
    fechaActivacion: DateTime(2026, 9, 24, 8),
  );

  late _RetosFalso repositorio;

  Future<void> abrirHistorial(
    WidgetTester tester, {
    Future<List<RetoDelUsuario>> Function()? respuesta,
    bool esperar = true,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = _RetosFalso(
      respuesta ??
          () async => [enCurso, completadoHoy, completadoAyer, vencido],
    );
    final router = GoRouter(
      initialLocation: '/retos/historial',
      routes: [
        GoRoute(
          path: '/retos',
          builder: (_, _) => const Scaffold(body: Text('Catálogo')),
          routes: [
            GoRoute(
              path: 'historial',
              builder: (_, _) => const HistorialRetosScreen(),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retosRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tocarChip(
    WidgetTester tester,
    SeccionHistorialRetos seccion,
  ) async {
    final chip = find.byKey(HistorialRetosScreen.claveChip(seccion));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  group('pestaña inicial', () {
    testWidgets('abre en En curso, que es lo único accionable', (tester) async {
      await abrirHistorial(tester);

      expect(find.text('Camina 3 km esta semana'), findsOneWidget);
      // Lo demás queda detrás de su chip, no debajo.
      expect(find.text('Corre 15 km'), findsNothing);
      expect(find.text('Corre 1 km hoy'), findsNothing);
    });

    testWidgets('muestra el progreso sobre la meta', (tester) async {
      await abrirHistorial(tester);

      expect(find.text('1.2 de 3 km'), findsOneWidget);
    });

    testWidgets('el progreso no arrastra los decimales de la división', (
      tester,
    ) async {
      await abrirHistorial(tester);
      await tocarChip(tester, SeccionHistorialRetos.vencidos);

      // 1/3 de km: sin redondeo se leería 0.3333333333333333.
      expect(find.text('0.33 de 1 km'), findsOneWidget);
    });
  });

  group('completados por fecha (SCRUM-174)', () {
    testWidgets('se agrupan por día, del más reciente al más antiguo', (
      tester,
    ) async {
      await abrirHistorial(tester);
      await tocarChip(tester, SeccionHistorialRetos.completados);

      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Ayer'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Hoy')).dy,
        lessThan(tester.getTopLeft(find.text('Ayer')).dy),
      );
    });

    testWidgets('los de hace más de dos días llevan su fecha', (tester) async {
      final viejo = RetoDelUsuario(
        reto: reto(id: 'e', nombre: 'Reto viejo', fin: DateTime(2026, 9, 13)),
        estado: EstadoRetoUsuario.completado,
        progresoKm: 15,
        fechaActivacion: DateTime(2026, 9, 7),
        fechaCompletado: DateTime(2026, 9, 13, 12),
      );
      await abrirHistorial(tester, respuesta: () async => [viejo]);
      await tocarChip(tester, SeccionHistorialRetos.completados);

      expect(find.text('13 sep'), findsOneWidget);
    });

    testWidgets('solo salen los completados', (tester) async {
      await abrirHistorial(tester);
      await tocarChip(tester, SeccionHistorialRetos.completados);

      expect(find.text('Corre 15 km'), findsOneWidget);
      expect(find.text('Trote de 8 km'), findsOneWidget);
      expect(find.text('Camina 3 km esta semana'), findsNothing);
    });
  });

  group('vencidos (SCRUM-173)', () {
    testWidgets('sale lo que se activó y no se completó a tiempo', (
      tester,
    ) async {
      await abrirHistorial(tester);
      await tocarChip(tester, SeccionHistorialRetos.vencidos);

      expect(find.text('Corre 1 km hoy'), findsOneWidget);
      expect(find.text('Camina 3 km esta semana'), findsNothing);
    });

    testWidgets('no se agrupan por fecha: lo que importa es el progreso', (
      tester,
    ) async {
      await abrirHistorial(tester);
      await tocarChip(tester, SeccionHistorialRetos.vencidos);

      expect(find.text('Hoy'), findsNothing);
      expect(find.text('Ayer'), findsNothing);
    });
  });

  group('pestañas vacías', () {
    testWidgets('cada una dice lo suyo', (tester) async {
      await abrirHistorial(tester, respuesta: () async => [enCurso]);

      await tocarChip(tester, SeccionHistorialRetos.completados);
      expect(find.text('Aún no has completado ningún reto'), findsOneWidget);

      await tocarChip(tester, SeccionHistorialRetos.vencidos);
      expect(find.text('No se te ha vencido ningún reto'), findsOneWidget);
    });

    testWidgets('sin ningún reto activado, tampoco se repite el mensaje', (
      tester,
    ) async {
      // Un texto común obligaría a mirar qué chip está activo para saber de
      // qué habla.
      await abrirHistorial(tester, respuesta: () async => []);
      expect(find.text('No tienes retos en curso'), findsOneWidget);

      await tocarChip(tester, SeccionHistorialRetos.completados);
      expect(find.text('Aún no has completado ningún reto'), findsOneWidget);
      expect(find.text('No tienes retos en curso'), findsNothing);
    });
  });

  group('carga y errores', () {
    testWidgets('mientras consulta muestra el indicador', (tester) async {
      final pendiente = Completer<List<RetoDelUsuario>>();
      await abrirHistorial(
        tester,
        respuesta: () => pendiente.future,
        esperar: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pendiente.complete([enCurso]);
      await tester.pumpAndSettle();
      expect(find.text('Camina 3 km esta semana'), findsOneWidget);
    });

    testWidgets('si falla lo dice y permite reintentar', (tester) async {
      var falla = true;
      await abrirHistorial(
        tester,
        respuesta: () async {
          if (falla) throw Exception('sin red');
          return [enCurso];
        },
      );

      expect(find.text('No pudimos cargar tus retos'), findsOneWidget);

      falla = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Camina 3 km esta semana'), findsOneWidget);
    });

    testWidgets('cambiar de pestaña no vuelve a consultar', (tester) async {
      await abrirHistorial(tester);
      final antes = repositorio.consultas;

      await tocarChip(tester, SeccionHistorialRetos.completados);

      expect(repositorio.consultas, antes);
    });
  });

  group('retos que el administrador retiró (SCRUM-160)', () {
    /// Lo mismo que `completadoAyer`, pero el reto ya no está publicado.
    final deUnoRetirado = RetoDelUsuario(
      reto: Reto(
        id: 'c',
        nombre: 'Trote de 8 km',
        descripcion: 'Qué hay que hacer.',
        periodicidad: PeriodicidadReto.semanal,
        metaKm: 8,
        xpOtorgada: 200,
        vigencia: VigenciaReto(
          inicio: DateTime(2026, 9, 21),
          fin: DateTime(2026, 9, 27),
        ),
        estado: EstadoReto.retirado,
        tipoActividad: const TipoActividad(id: 'tipo-correr', nombre: 'Correr'),
      ),
      estado: EstadoRetoUsuario.completado,
      progresoKm: 8,
      fechaActivacion: DateTime(2026, 9, 21, 8),
      fechaCompletado: DateTime(2026, 9, 27, 18),
    );

    testWidgets('lo completado se conserva aunque el reto ya no exista', (
      tester,
    ) async {
      // Criterio 3: retirar saca el reto del catálogo, no del historial de
      // quien lo cumplió. Que la fila llegue entera depende de la policy de
      // 0018; esta prueba cubre que la pantalla no lo esconda después.
      await abrirHistorial(tester, respuesta: () async => [deUnoRetirado]);

      await tocarChip(tester, SeccionHistorialRetos.completados);

      expect(find.text('Trote de 8 km'), findsOneWidget);
      expect(find.text('+200 XP'), findsOneWidget);
    });

    testWidgets('con su progreso y su meta, como cualquier otro', (
      tester,
    ) async {
      await abrirHistorial(tester, respuesta: () async => [deUnoRetirado]);

      await tocarChip(tester, SeccionHistorialRetos.completados);

      expect(find.text('8 de 8 km'), findsOneWidget);
    });
  });
}
