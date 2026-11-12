import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/recorrido_local.dart';
import 'package:traza/screens/sincronizacion/sincronizacion_screen.dart';
import 'package:traza/services/almacen_recorrido.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/widgets/aviso_sincronizacion.dart';

import '../utiles/almacen_recorrido_falso.dart';
import '../utiles/recorrido_local_de_prueba.dart';

void main() {
  Future<void> montar(
    WidgetTester tester, {
    List<RecorridoLocal> recorridos = const [],
    String? enCurso,
  }) async {
    final almacen = AlmacenRecorridoFalso()..recorridos = recorridos;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              const Scaffold(body: Column(children: [AvisoSincronizacion()])),
        ),
        GoRoute(
          path: SincronizacionScreen.ruta,
          builder: (_, _) =>
              const Scaffold(body: Text('Pantalla de sincronización')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          almacenRecorridoProvider.overrideWithValue(almacen),
          entrenamientoActualProvider.overrideWithValue(enCurso),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sin nada por subir no ocupa lugar en la portada', (
    tester,
  ) async {
    await montar(tester, recorridos: [recorridoSubidoDePrueba('ent-1')]);

    expect(find.byKey(AvisoSincronizacion.clave), findsNothing);
  });

  testWidgets('dice cuántos recorridos faltan por subir', (tester) async {
    await montar(
      tester,
      recorridos: [
        recorridoLocalDePrueba('ent-1'),
        recorridoFallidoDePrueba('ent-2'),
      ],
    );

    expect(find.text(AvisoSincronizacion.titulo(2)), findsOneWidget);
    expect(
      find.text('Se suben solos con conexión. Toca para ver'),
      findsOneWidget,
    );
  });

  testWidgets('si la base rechazó alguno, lo dice: no se arregla solo', (
    tester,
  ) async {
    await montar(
      tester,
      recorridos: [
        recorridoLocalDePrueba('ent-1'),
        recorridoRechazadoDePrueba('ent-2'),
      ],
    );

    expect(
      find.text('La base no aceptó 1. Toca para ver qué hacer'),
      findsOneWidget,
    );
  });

  testWidgets('no cuenta el entrenamiento en curso, que se sube mientras se '
      'corre', (tester) async {
    await montar(
      tester,
      enCurso: 'ent-en-curso',
      recorridos: [recorridoLocalDePrueba('ent-en-curso')],
    );

    expect(find.byKey(AvisoSincronizacion.clave), findsNothing);
  });

  testWidgets('al tocarlo abre la pantalla de sincronización', (tester) async {
    await montar(tester, recorridos: [recorridoLocalDePrueba('ent-1')]);

    await tester.tap(find.byKey(AvisoSincronizacion.clave));
    await tester.pumpAndSettle();

    expect(find.text('Pantalla de sincronización'), findsOneWidget);
  });
}
