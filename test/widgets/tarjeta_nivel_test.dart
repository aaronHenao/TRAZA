import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/screens/home/mapa_progresion_screen.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/widgets/barra_progresion.dart';
import 'package:traza/widgets/tarjeta_nivel.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';

/// Pruebas de la tarjeta de nivel de la portada (SCRUM-286).
///
/// Es el criterio 1 de SCRUM-283: el nivel actual, la experiencia acumulada,
/// la que falta para el siguiente y la barra de avance, todo sin salir de la
/// portada. Al tocarla se abre el mapa de progresión.
void main() {
  const niveles = [
    Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100),
    Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500),
    Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500),
  ];

  group('los datos del criterio 1', () {
    testWidgets('muestra el número y el nombre del nivel, la XP y lo que '
        'falta', (tester) async {
      await _montar(tester, niveles: niveles, experiencia: 250);

      expect(find.text('NIVEL 1'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(TarjetaNivel.claveNivel)).data,
        'Bronce',
      );
      expect(
        tester.widget<Text>(find.byKey(TarjetaNivel.claveExperiencia)).data,
        '250 XP acumulados',
      );
      expect(
        tester.widget<Text>(find.byKey(TarjetaNivel.claveFaltante)).data,
        'Te faltan 250 XP para Plata.',
      );
    });

    testWidgets('el número cuenta los niveles de abajo arriba', (tester) async {
      // 600 XP: pasó Bronce y Plata, así que va en el segundo nivel.
      await _montar(tester, niveles: niveles, experiencia: 600);

      expect(find.text('NIVEL 2'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(TarjetaNivel.claveNivel)).data,
        'Plata',
      );
      expect(
        tester.widget<Text>(find.byKey(TarjetaNivel.claveFaltante)).data,
        'Te faltan 900 XP para Oro.',
      );
    });

    testWidgets('lleva la barra con el avance del tramo', (tester) async {
      // 300 de los 400 XP que van de Bronce a Plata: la mitad del tramo.
      await _montar(tester, niveles: niveles, experiencia: 300);

      final barra = tester.widget<LinearProgressIndicator>(
        find.byKey(BarraProgresion.clave),
      );
      expect(barra.value, closeTo(0.5, 0.001));
      expect(find.text('200 de 400 XP'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });
  });

  group('casos borde', () {
    testWidgets('sin ningún nivel alcanzado lo dice, no muestra "Nivel 0"', (
      tester,
    ) async {
      await _montar(tester, niveles: niveles, experiencia: 40);

      expect(find.text('TU NIVEL'), findsOneWidget);
      expect(find.textContaining('NIVEL 0'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(TarjetaNivel.claveNivel)).data,
        'Aún sin nivel',
      );
      // El primer nivel sigue siendo una meta: la barra cuenta hacia él.
      expect(
        tester.widget<Text>(find.byKey(TarjetaNivel.claveFaltante)).data,
        'Te faltan 60 XP para Bronce.',
      );
      expect(find.byKey(BarraProgresion.clave), findsOneWidget);
    });

    testWidgets('en el nivel más alto no hay falta ni barra que mostrar', (
      tester,
    ) async {
      await _montar(tester, niveles: niveles, experiencia: 2000);

      expect(find.text('NIVEL 3'), findsOneWidget);
      expect(find.text('Estás en el nivel más alto'), findsOneWidget);
      expect(find.byKey(TarjetaNivel.claveFaltante), findsNothing);
      expect(find.byKey(BarraProgresion.clave), findsNothing);
    });

    testWidgets('sin niveles configurados avisa en lugar de fallar', (
      tester,
    ) async {
      await _montar(tester, niveles: const [], experiencia: 250);

      expect(find.text('Todavía no hay niveles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mientras consulta no deja la tarjeta en blanco', (
      tester,
    ) async {
      final pendiente = Completer<List<Nivel>>();
      await _montar(
        tester,
        niveles: niveles,
        experiencia: 250,
        nivelesPendientes: pendiente,
        esperar: false,
      );

      expect(find.text('Cargando tu nivel…'), findsOneWidget);

      pendiente.complete(niveles);
      await tester.pumpAndSettle();
      expect(find.text('Bronce'), findsOneWidget);
    });

    testWidgets('si no se puede consultar, lo dice y ofrece reintentar', (
      tester,
    ) async {
      await _montar(
        tester,
        niveles: niveles,
        experiencia: 250,
        errorAlListar: Exception('sin red'),
      );

      expect(find.text('No pudimos cargar tu nivel'), findsOneWidget);
      expect(find.textContaining('Desliza hacia abajo'), findsOneWidget);
    });
  });

  group('al tocarla', () {
    testWidgets('abre el mapa de progresión', (tester) async {
      final router = await _montar(tester, niveles: niveles, experiencia: 250);

      await tester.tap(find.byKey(TarjetaNivel.clave));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Mapa'), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        MapaProgresionScreen.ruta,
      );
    });

    testWidgets('sin niveles también abre el mapa', (tester) async {
      // El mapa sabe decir que todavía no hay camino (SCRUM-226): la tarjeta
      // no tiene que bloquear la entrada.
      await _montar(tester, niveles: const [], experiencia: 0);

      await tester.tap(find.byKey(TarjetaNivel.clave));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Mapa'), findsOneWidget);
    });

    testWidgets('el mapa reemplaza la portada: no se apila encima', (
      tester,
    ) async {
      final router = await _montar(tester, niveles: niveles, experiencia: 250);

      await tester.tap(find.byKey(TarjetaNivel.clave));
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.matches.length, 1);
    });
  });

  testWidgets('en la pantalla más estrecha no desborda', (tester) async {
    await _montar(
      tester,
      niveles: niveles,
      experiencia: 250,
      tamano: const Size(320, 568),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('NIVEL 1'), findsOneWidget);
    expect(find.byKey(BarraProgresion.clave), findsOneWidget);
  });
}

/// Monta la tarjeta como la monta la portada: en una pantalla con la ruta del
/// mapa al lado, para poder tocarla y ver a dónde lleva.
Future<GoRouter> _montar(
  WidgetTester tester, {
  required List<Nivel> niveles,
  required int experiencia,
  Completer<List<Nivel>>? nivelesPendientes,
  Object? errorAlListar,
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
          body: Padding(padding: EdgeInsets.all(20), child: TarjetaNivel()),
        ),
      ),
      GoRoute(
        path: MapaProgresionScreen.ruta,
        builder: (_, _) => const Scaffold(body: Text('Pantalla Mapa')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nivelesRepositoryProvider.overrideWithValue(
          nivelesPendientes == null
              ? (NivelesFalso(catalogo: niveles)..errorAlListar = errorAlListar)
              : _NivelesPendientes(nivelesPendientes),
        ),
        experienciaRepositoryProvider.overrideWithValue(
          ExperienciaFalsa(acumulada: experiencia),
        ),
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

/// Niveles que no responden hasta que la prueba lo decida.
class _NivelesPendientes extends NivelesFalso {
  _NivelesPendientes(this.espera);

  final Completer<List<Nivel>> espera;

  @override
  Future<List<Nivel>> listar() => espera.future;
}
