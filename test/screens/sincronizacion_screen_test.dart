import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/recorrido_local.dart';
import 'package:traza/screens/sincronizacion/sincronizacion_screen.dart';
import 'package:traza/services/almacen_recorrido.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/reenvio_recorridos.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/sincronizacion_provider.dart';

import '../utiles/almacen_recorrido_falso.dart';
import '../utiles/recorrido_local_de_prueba.dart';
import '../utiles/reloj_falso.dart';

void main() {
  late AlmacenRecorridoFalso almacen;

  /// Cuántas veces se lanzó el reenvío, y cuántos recorridos "sube".
  var reenvios = 0;
  var subeAlReintentar = 0;

  setUp(() {
    almacen = AlmacenRecorridoFalso();
    reenvios = 0;
    subeAlReintentar = 0;
  });

  Future<void> montar(
    WidgetTester tester, {
    List<RecorridoLocal> recorridos = const [],
    String? enCurso,
  }) async {
    almacen.recorridos = recorridos;
    final router = GoRouter(
      initialLocation: '/origen',
      routes: [
        GoRoute(
          path: '/origen',
          builder: (_, _) => const Scaffold(body: Text('Portada')),
        ),
        GoRoute(
          path: SincronizacionScreen.ruta,
          builder: (_, _) => const SincronizacionScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          almacenRecorridoProvider.overrideWithValue(almacen),
          reenvioRecorridosProvider.overrideWith((ref) async {
            reenvios++;
            return subeAlReintentar;
          }),
          relojProvider.overrideWithValue(
            RelojFalso(DateTime(2026, 11, 11, 12)).call,
          ),
          entrenamientoActualProvider.overrideWithValue(enCurso),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push(SincronizacionScreen.ruta);
    await tester.pumpAndSettle();
  }

  testWidgets('sin nada por subir dice que todo está subido', (tester) async {
    await montar(tester);

    expect(find.text(SincronizacionScreen.todoSubido), findsOneWidget);
    expect(find.byKey(SincronizacionScreen.claveReintentar), findsNothing);
  });

  testWidgets('separa el estado del entrenamiento del de su subida', (
    tester,
  ) async {
    await montar(tester, recorridos: [recorridoLocalDePrueba('ent-1')]);

    expect(find.text(SincronizacionScreen.explicacion), findsOneWidget);
    expect(
      find.text(SincronizacionScreen.entrenamientoGuardado),
      findsOneWidget,
    );
    expect(
      find.text('Pendiente de subir · 3 puntos sin subir'),
      findsOneWidget,
    );
  });

  testWidgets('muestra cada estado con el motivo de lo que falló', (
    tester,
  ) async {
    await montar(
      tester,
      recorridos: [
        recorridoLocalDePrueba('ent-1'),
        recorridoFallidoDePrueba('ent-2'),
        recorridoRechazadoDePrueba('ent-3'),
      ],
    );

    expect(find.textContaining('Pendiente de subir'), findsOneWidget);
    expect(find.textContaining('No se pudo subir'), findsOneWidget);
    expect(find.textContaining('Rechazado por la base'), findsOneWidget);
    expect(find.text(RecorridoLocal.motivoSinEnviar), findsOneWidget);
    expect(find.text(RecorridoLocal.motivoRechazado), findsOneWidget);
  });

  testWidgets('no muestra lo que ya subió ni el entrenamiento en curso', (
    tester,
  ) async {
    await montar(
      tester,
      enCurso: 'ent-en-curso',
      recorridos: [
        recorridoSubidoDePrueba('ent-subido'),
        recorridoLocalDePrueba('ent-en-curso'),
        recorridoLocalDePrueba('ent-1'),
      ],
    );

    expect(find.byKey(SincronizacionScreen.claveFila('ent-1')), findsOneWidget);
    expect(
      find.byKey(SincronizacionScreen.claveFila('ent-subido')),
      findsNothing,
    );
    expect(
      find.byKey(SincronizacionScreen.claveFila('ent-en-curso')),
      findsNothing,
    );
  });

  group('reintentar', () {
    testWidgets('lanza el reenvío y dice cuántos subió', (tester) async {
      subeAlReintentar = 2;
      await montar(
        tester,
        recorridos: [
          recorridoLocalDePrueba('ent-1'),
          recorridoFallidoDePrueba('ent-2'),
        ],
      );

      await tester.tap(find.byKey(SincronizacionScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(reenvios, 1);
      expect(find.text(SincronizacionRecorridos.subidos(2)), findsOneWidget);
    });

    testWidgets('si no subió nada, lo avisa sin borrar la lista', (
      tester,
    ) async {
      await montar(tester, recorridos: [recorridoFallidoDePrueba('ent-1')]);

      await tester.tap(find.byKey(SincronizacionScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.text(SincronizacionRecorridos.sinSubir), findsOneWidget);
      expect(
        find.byKey(SincronizacionScreen.claveFila('ent-1')),
        findsOneWidget,
      );
    });

    testWidgets('no se ofrece si solo hay rechazados: la base los volvería a '
        'rechazar', (tester) async {
      await montar(tester, recorridos: [recorridoRechazadoDePrueba('ent-1')]);

      expect(find.byKey(SincronizacionScreen.claveReintentar), findsNothing);
    });
  });

  group('descartar', () {
    testWidgets('solo se ofrece en lo rechazado', (tester) async {
      await montar(
        tester,
        recorridos: [
          recorridoLocalDePrueba('ent-1'),
          recorridoFallidoDePrueba('ent-2'),
          recorridoRechazadoDePrueba('ent-3'),
        ],
      );

      expect(
        find.byKey(SincronizacionScreen.claveDescartar('ent-1')),
        findsNothing,
      );
      expect(
        find.byKey(SincronizacionScreen.claveDescartar('ent-2')),
        findsNothing,
      );
      expect(
        find.byKey(SincronizacionScreen.claveDescartar('ent-3')),
        findsOneWidget,
      );
    });

    testWidgets('pide confirmación y borra el recorrido del teléfono', (
      tester,
    ) async {
      await montar(tester, recorridos: [recorridoRechazadoDePrueba('ent-3')]);

      await tester.tap(
        find.byKey(SincronizacionScreen.claveDescartar('ent-3')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Descartar recorrido'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
      await tester.pumpAndSettle();

      expect(almacen.olvidados, ['ent-3']);
      expect(find.text(SincronizacionRecorridos.descartado), findsOneWidget);
    });

    testWidgets('al cancelar no borra nada', (tester) async {
      await montar(tester, recorridos: [recorridoRechazadoDePrueba('ent-3')]);

      await tester.tap(
        find.byKey(SincronizacionScreen.claveDescartar('ent-3')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(almacen.olvidados, isEmpty);
    });
  });

  testWidgets('si no se puede leer el teléfono, lo dice y deja reintentar', (
    tester,
  ) async {
    almacen.error = Exception('disco no disponible');
    await montar(tester);

    expect(find.text(SincronizacionScreen.sinLectura), findsOneWidget);

    almacen.error = null;
    almacen.recorridos = [recorridoLocalDePrueba('ent-1')];
    await tester.tap(find.byKey(SincronizacionScreen.claveReintentarLectura));
    await tester.pumpAndSettle();

    expect(find.byKey(SincronizacionScreen.claveFila('ent-1')), findsOneWidget);
  });
}
