import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/insignia.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/screens/home/progresion_screen.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/insignias_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/widgets/barra_progresion.dart';
import 'package:traza/widgets/seccion_insignias.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/insignias_falsas.dart';
import '../utiles/niveles_falso.dart';

/// Pruebas de la pantalla de requisitos del siguiente nivel (SCRUM-187).
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const niveles = [bronce, plata];

  testWidgets('muestra el nivel actual, la experiencia, el umbral del '
      'siguiente y lo que falta', (tester) async {
    await _montar(tester, catalogo: niveles, experiencia: 300);

    expect(_texto(tester, ProgresionScreen.claveNivelActual), 'Bronce');
    expect(
      _texto(tester, ProgresionScreen.claveExperiencia),
      '300 XP acumulados',
    );
    expect(find.text('Plata'), findsOneWidget);
    expect(find.text('500 XP'), findsOneWidget);
    expect(
      _texto(tester, ProgresionScreen.claveFaltante),
      'Te faltan 200 XP para alcanzarlo.',
    );
  });

  group('barra de progreso (SCRUM-208)', () {
    double? avance(WidgetTester tester) => tester
        .widget<LinearProgressIndicator>(
          find.byKey(ProgresionScreen.claveAvance),
        )
        .value;

    testWidgets('dibuja lo recorrido del tramo hacia el siguiente nivel', (
      tester,
    ) async {
      await _montar(tester, catalogo: niveles, experiencia: 300);

      // 200 de los 400 que hay entre Bronce y Plata.
      expect(avance(tester), 0.5);
    });

    testWidgets('sin nivel todavía, el tramo empieza en cero', (tester) async {
      await _montar(tester, catalogo: niveles, experiencia: 25);

      expect(avance(tester), 0.25);
    });

    testWidgets('en el nivel más alto no hay barra hacia ninguna parte', (
      tester,
    ) async {
      await _montar(tester, catalogo: niveles, experiencia: 900);

      expect(find.byKey(ProgresionScreen.claveAvance), findsNothing);
    });

    testWidgets('al refrescar refleja la XP nueva', (tester) async {
      final experiencia = ExperienciaFalsa(acumulada: 300);
      await _montar(
        tester,
        catalogo: niveles,
        repositorioExperiencia: experiencia,
      );

      experiencia.acumulada = 400;
      await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      expect(avance(tester), 0.75);
    });
  });

  testWidgets('sin nivel alcanzado todavía lo dice en vez de dejarlo en '
      'blanco', (tester) async {
    await _montar(tester, catalogo: niveles, experiencia: 40);

    expect(_texto(tester, ProgresionScreen.claveNivelActual), 'Aún sin nivel');
    expect(find.text('Bronce'), findsOneWidget);
    expect(
      _texto(tester, ProgresionScreen.claveFaltante),
      'Te faltan 60 XP para alcanzarlo.',
    );
  });

  testWidgets('acompaña los números con la barra de avance', (tester) async {
    // De Bronce (100) a Plata (500) hay 400; con 300 lleva la mitad.
    await _montar(tester, catalogo: niveles, experiencia: 300);

    expect(find.byType(BarraProgresion), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byKey(BarraProgresion.clave))
          .value,
      closeTo(0.5, 0.0001),
    );
  });

  testWidgets('en el nivel más alto no muestra un siguiente inexistente', (
    tester,
  ) async {
    await _montar(tester, catalogo: niveles, experiencia: 900);

    expect(_texto(tester, ProgresionScreen.claveNivelActual), 'Plata');
    expect(find.text('Estás en el nivel más alto'), findsOneWidget);
    expect(find.byKey(ProgresionScreen.claveFaltante), findsNothing);
    expect(find.text('SIGUIENTE NIVEL'), findsNothing);
    // Sin siguiente nivel no hay barra que llenar.
    expect(find.byKey(BarraProgresion.clave), findsNothing);
  });

  testWidgets('sin niveles configurados avisa, no falla', (tester) async {
    await _montar(tester, catalogo: const [], experiencia: 300);

    expect(find.text('Todavía no hay niveles'), findsOneWidget);
    expect(find.byKey(ProgresionScreen.claveNivelActual), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si la consulta falla, avisa y permite reintentar', (
    tester,
  ) async {
    final repositorio = NivelesFalso(catalogo: niveles)
      ..errorAlListar = StateError('sin conexión');
    await _montar(tester, repositorioNiveles: repositorio, experiencia: 300);

    expect(find.text('No pudimos cargar tu progresión'), findsOneWidget);

    repositorio.errorAlListar = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reintentar'));
    await tester.pumpAndSettle();

    expect(_texto(tester, ProgresionScreen.claveNivelActual), 'Bronce');
  });

  testWidgets('al refrescar refleja la experiencia ganada desde la última '
      'visita', (tester) async {
    final experiencia = ExperienciaFalsa(acumulada: 300);
    await _montar(
      tester,
      catalogo: niveles,
      repositorioExperiencia: experiencia,
    );

    expect(_texto(tester, ProgresionScreen.claveNivelActual), 'Bronce');

    // El corredor completó un reto y el motor le acreditó la XP.
    experiencia.acumulada = 600;
    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(_texto(tester, ProgresionScreen.claveNivelActual), 'Plata');
    expect(
      _texto(tester, ProgresionScreen.claveExperiencia),
      '600 XP acumulados',
    );
  });

  group('insignias (SCRUM-193, criterio 6)', () {
    final primeraHuella = Insignia(
      id: 'i-1',
      nombre: 'Primera huella',
      descripcion: 'Tu primer kilómetro con TRAZA',
      icono: 'huella',
      xpRequerida: 5,
      obtenidaEl: DateTime.utc(2026, 9, 20, 15),
    );
    const diezMil = Insignia(
      id: 'i-3',
      nombre: 'Diez mil',
      descripcion: 'Tus primeros 10 km en una salida',
      icono: 'diez',
      xpRequerida: 105,
    );

    Finder dentroDe(String id, Finder buscado) => find.descendant(
      of: find.byKey(ValueKey('insignia-$id')),
      matching: buscado,
    );

    testWidgets('con niveles, las insignias obtenidas se ven debajo de la '
        'progresión', (tester) async {
      await _montar(
        tester,
        catalogo: niveles,
        experiencia: 300,
        insignias: [primeraHuella, diezMil],
      );

      expect(find.byKey(SeccionInsignias.clave), findsOneWidget);
      expect(dentroDe('i-1', find.text('Primera huella')), findsOneWidget);
      expect(dentroDe('i-1', find.text('Obtenida')), findsOneWidget);
      expect(dentroDe('i-3', find.text('Obtenida')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(SeccionInsignias.clave)).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(ProgresionScreen.claveNivelActual)).dy,
        ),
      );
    });

    testWidgets('sin niveles configurados también se ven las insignias', (
      tester,
    ) async {
      // Las insignias dependen de la XP, no de que el administrador haya
      // creado niveles.
      await _montar(
        tester,
        catalogo: const [],
        experiencia: 300,
        insignias: [primeraHuella],
      );

      expect(find.text('Todavía no hay niveles'), findsOneWidget);
      expect(find.byKey(SeccionInsignias.clave), findsOneWidget);
      expect(dentroDe('i-1', find.text('Obtenida')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(SeccionInsignias.clave)).dy,
        greaterThan(tester.getTopLeft(find.text('Todavía no hay niveles')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('al refrescar se ven las insignias ganadas desde la última '
        'visita', (tester) async {
      final insignias = InsigniasFalsas(catalogo: const [diezMil]);
      await _montar(
        tester,
        catalogo: niveles,
        experiencia: 300,
        repositorioInsignias: insignias,
      );

      expect(dentroDe('i-3', find.text('Obtenida')), findsNothing);
      final consultasAntes = insignias.consultas;

      // El trigger se la otorgó en un entrenamiento posterior.
      insignias.catalogo = [
        Insignia(
          id: 'i-3',
          nombre: 'Diez mil',
          descripcion: 'Tus primeros 10 km en una salida',
          icono: 'diez',
          xpRequerida: 105,
          obtenidaEl: DateTime.utc(2026, 9, 28, 7),
        ),
      ];
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(insignias.consultas, greaterThan(consultasAntes));
      expect(dentroDe('i-3', find.text('Obtenida')), findsOneWidget);
    });
  });
}

String _texto(WidgetTester tester, Key clave) =>
    tester.widget<Text>(find.byKey(clave)).data!;

/// Abre la pantalla de progresión con los datos que indique la prueba.
Future<void> _montar(
  WidgetTester tester, {
  List<Nivel> catalogo = const [],
  NivelesFalso? repositorioNiveles,
  int experiencia = 0,
  ExperienciaFalsa? repositorioExperiencia,
  List<Insignia> insignias = const [],
  InsigniasFalsas? repositorioInsignias,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: ProgresionScreen.ruta,
    routes: [
      GoRoute(
        path: ProgresionScreen.ruta,
        builder: (_, _) => const ProgresionScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nivelesRepositoryProvider.overrideWithValue(
          repositorioNiveles ?? NivelesFalso(catalogo: catalogo),
        ),
        experienciaRepositoryProvider.overrideWithValue(
          repositorioExperiencia ?? ExperienciaFalsa(acumulada: experiencia),
        ),
        insigniasRepositoryProvider.overrideWithValue(
          repositorioInsignias ?? InsigniasFalsas(catalogo: insignias),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
