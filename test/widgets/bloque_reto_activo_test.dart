import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/widgets/bloque_reto_activo.dart';
import 'package:traza/widgets/fila_reto_usuario.dart';

import '../utiles/retos_repository_falso.dart';

/// Retos de mentira: devuelve los que el corredor tendría activados.
class _RetosFalsos extends RetosRepositorioFalso {
  _RetosFalsos(this.respuesta);

  Future<List<RetoDelUsuario>> Function() respuesta;

  @override
  Future<List<RetoDelUsuario>> misRetos() => respuesta();
}

/// Pruebas del bloque de reto activo de la portada (SCRUM-288).
///
/// Es el criterio 3 de SCRUM-283: el reto en curso con su avance, y al tocarlo
/// la sección de Retos.
void main() {
  // Miércoles 16 de septiembre.
  final ahora = DateTime(2026, 9, 16, 10);

  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');

  Reto reto({
    required String id,
    required String nombre,
    double metaKm = 20,
    DateTime? inicio,
    DateTime? fin,
  }) => Reto(
    id: id,
    nombre: nombre,
    descripcion: 'Qué hay que hacer en $nombre.',
    periodicidad: PeriodicidadReto.semanal,
    metaKm: metaKm,
    xpOtorgada: 100,
    vigencia: VigenciaReto(
      inicio: inicio ?? DateTime(2026, 9, 14),
      fin: fin ?? DateTime(2026, 9, 20),
    ),
    estado: EstadoReto.activo,
    tipoActividad: correr,
  );

  RetoDelUsuario mio(
    Reto cual, {
    double progresoKm = 8,
    EstadoRetoUsuario estado = EstadoRetoUsuario.enProgreso,
    DateTime? completadoEl,
  }) => RetoDelUsuario(
    reto: cual,
    estado: estado,
    progresoKm: progresoKm,
    fechaActivacion: DateTime(2026, 9, 14, 8),
    fechaCompletado: completadoEl,
  );

  final semanal = reto(id: 'r-1', nombre: 'Corre 20 km esta semana');

  Future<GoRouter> montar(
    WidgetTester tester, {
    Future<List<RetoDelUsuario>> Function()? retos,
    bool esperar = true,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: BloqueRetoActivo(),
            ),
          ),
        ),
        GoRoute(
          path: BloqueRetoActivo.rutaRetos,
          builder: (_, _) => const Scaffold(body: Text('Sección de Retos')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retosRepositoryProvider.overrideWithValue(
            _RetosFalsos(retos ?? () async => [mio(semanal)]),
          ),
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
    return router;
  }

  group('el reto en curso', () {
    testWidgets('muestra su nombre, su avance y el conteo', (tester) async {
      await montar(tester);

      expect(find.text('RETO ACTIVO'), findsOneWidget);
      expect(find.byKey(BloqueRetoActivo.clave), findsOneWidget);
      expect(find.text('Corre 20 km esta semana'), findsOneWidget);
      // El conteo y la barra son los de la fila de la sección de Retos.
      expect(find.text('8 de 20 km'), findsOneWidget);
      expect(find.text('100 XP'), findsOneWidget);

      final barra = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: find.byType(FilaRetoUsuario),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(barra.value, closeTo(0.4, 0.001));
    });

    testWidgets('destaca el que se acaba primero', (tester) async {
      final mensual = reto(
        id: 'r-2',
        nombre: 'Corre 60 km este mes',
        fin: DateTime(2026, 9, 30),
      );
      final hoy = reto(
        id: 'r-3',
        nombre: 'Corre 5 km hoy',
        metaKm: 5,
        inicio: DateTime(2026, 9, 16),
        fin: DateTime(2026, 9, 16),
      );

      await montar(
        tester,
        retos: () async => [mio(mensual), mio(semanal), mio(hoy)],
      );

      expect(find.text('Corre 5 km hoy'), findsOneWidget);
      expect(find.text('Corre 20 km esta semana'), findsNothing);
      expect(find.text('Corre 60 km este mes'), findsNothing);
    });

    testWidgets('entre dos que terminan igual, el más avanzado', (
      tester,
    ) async {
      final otro = reto(id: 'r-4', nombre: 'Camina 20 km esta semana');

      await montar(
        tester,
        retos: () async => [
          mio(semanal, progresoKm: 3),
          mio(otro, progresoKm: 15),
        ],
      );

      expect(find.text('Camina 20 km esta semana'), findsOneWidget);
      expect(find.text('Corre 20 km esta semana'), findsNothing);
    });

    testWidgets('los completados y los vencidos no se destacan', (
      tester,
    ) async {
      final completado = mio(
        reto(id: 'r-5', nombre: 'Reto ya cumplido'),
        progresoKm: 20,
        estado: EstadoRetoUsuario.completado,
        completadoEl: DateTime(2026, 9, 15, 9),
      );
      final vencido = mio(
        reto(
          id: 'r-6',
          nombre: 'Reto de la semana pasada',
          inicio: DateTime(2026, 9, 7),
          fin: DateTime(2026, 9, 13),
        ),
        progresoKm: 2,
      );

      await montar(tester, retos: () async => [completado, vencido]);

      expect(find.byKey(BloqueRetoActivo.claveSinRetos), findsOneWidget);
      expect(find.text('Reto ya cumplido'), findsNothing);
      expect(find.text('Reto de la semana pasada'), findsNothing);
    });
  });

  group('al tocarlo', () {
    testWidgets('abre la sección de Retos, no el detalle del reto', (
      tester,
    ) async {
      final router = await montar(tester);

      await tester.tap(find.text('Corre 20 km esta semana'));
      await tester.pumpAndSettle();

      expect(find.text('Sección de Retos'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        BloqueRetoActivo.rutaRetos,
      );
    });

    testWidgets('la sección reemplaza la portada: no se apila encima', (
      tester,
    ) async {
      final router = await montar(tester);

      await tester.tap(find.text('Corre 20 km esta semana'));
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.matches.length, 1);
    });

    testWidgets('sin retos, la invitación también lleva a Retos', (
      tester,
    ) async {
      await montar(tester, retos: () async => const []);

      await tester.tap(find.byKey(BloqueRetoActivo.claveSinRetos));
      await tester.pumpAndSettle();

      expect(find.text('Sección de Retos'), findsOneWidget);
    });
  });

  group('cuando no hay reto que mostrar', () {
    testWidgets('sin ninguno activado invita a activar uno', (tester) async {
      await montar(tester, retos: () async => const []);

      expect(find.text('RETO ACTIVO'), findsOneWidget);
      expect(find.text('Activa un reto y empieza a ganar XP.'), findsOneWidget);
      expect(find.byType(FilaRetoUsuario), findsNothing);
    });

    testWidgets('mientras consulta lo dice', (tester) async {
      final pendiente = Completer<List<RetoDelUsuario>>();
      await montar(tester, retos: () => pendiente.future, esperar: false);

      expect(find.text('Cargando tus retos…'), findsOneWidget);

      pendiente.complete([mio(semanal)]);
      await tester.pumpAndSettle();
      expect(find.text('Corre 20 km esta semana'), findsOneWidget);
    });

    testWidgets('si no se puede consultar, lo dice sin romper la portada', (
      tester,
    ) async {
      await montar(tester, retos: () async => throw Exception('sin red'));

      expect(
        find.textContaining('No pudimos cargar tus retos'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('en la pantalla más estrecha no desborda', (tester) async {
    await montar(tester, tamano: const Size(320, 568));

    expect(tester.takeException(), isNull);
    expect(find.text('8 de 20 km'), findsOneWidget);
  });
}
