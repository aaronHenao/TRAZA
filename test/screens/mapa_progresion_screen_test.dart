import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/screens/home/mapa_progresion_screen.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/widgets/camino_progresion.dart';
import 'package:traza/widgets/navegacion_principal.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';

/// Pruebas de la pantalla del mapa de progresión (SCRUM-226).
///
/// La pantalla se monta sola: la barra inferior la pone el router, no ella.
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const oro = Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500);
  const niveles = [bronce, plata, oro];

  final marcador = find.byKey(CaminoProgresion.claveMarcador);

  Finder enTramo(int indice) => find.descendant(
    of: find.byKey(ValueKey('tramo-$indice')),
    matching: marcador,
  );

  Finder enParada(int indice) => find.descendant(
    of: find.byKey(ValueKey('parada-$indice')),
    matching: marcador,
  );

  Future<void> refrescar(WidgetTester tester) async {
    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tiene el título "Mapa de progresión"', (tester) async {
    await _montar(tester, catalogo: niveles, experiencia: 700);

    expect(find.text('Mapa de progresión'), findsOneWidget);
  });

  testWidgets('criterio 1: con progreso, muestra el camino, la XP y dónde '
      'está el usuario', (tester) async {
    await _montar(tester, catalogo: niveles, experiencia: 700);

    expect(find.byType(CaminoProgresion), findsOneWidget);
    expect(find.textContaining('700 XP'), findsOneWidget);
    expect(marcador, findsOneWidget);
    // Pasó Plata y va hacia Oro.
    expect(enTramo(2), findsOneWidget);
    expect(find.text('Todavía no hay niveles'), findsNothing);
  });

  testWidgets('criterio 2: sin ningún avance, ubica al usuario en el punto '
      'inicial', (tester) async {
    await _montar(tester, catalogo: niveles, experiencia: 0);

    expect(find.byType(CaminoProgresion), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget);
    expect(enTramo(0), findsOneWidget);
    expect(marcador, findsOneWidget);
  });

  testWidgets('sin niveles configurados, deja al usuario en el inicio y lo '
      'avisa', (tester) async {
    await _montar(tester, catalogo: const [], experiencia: 300);

    expect(find.text('Todavía no hay niveles'), findsOneWidget);
    expect(find.byType(CaminoProgresion), findsOneWidget);
    expect(enParada(0), findsOneWidget);
    expect(find.byKey(const ValueKey('parada-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('criterio 3: al refrescar tras ganar XP, el marcador pasa a la '
      'nueva posición', (tester) async {
    final experiencia = ExperienciaFalsa(acumulada: 300);
    await _montar(
      tester,
      catalogo: niveles,
      repositorioExperiencia: experiencia,
    );

    expect(enTramo(1), findsOneWidget);
    final consultasAntes = experiencia.consultas;

    // El entrenamiento que acaba de cerrar le acreditó XP (trigger).
    experiencia.acumulada = 600;
    await refrescar(tester);

    expect(experiencia.consultas, greaterThan(consultasAntes));
    expect(enTramo(2), findsOneWidget);
    expect(enTramo(1), findsNothing);
    expect(find.textContaining('600 XP'), findsOneWidget);
  });

  group('criterio 5: si no carga', () {
    testWidgets('avisa que el mapa no pudo cargarse y "Reintentar" vuelve a '
        'consultar y lo muestra', (tester) async {
      final experiencia = ExperienciaFalsa(acumulada: 700)
        ..error = StateError('PostgrestException: permission denied');
      await _montar(
        tester,
        catalogo: niveles,
        repositorioExperiencia: experiencia,
      );

      expect(
        find.text('No pudimos cargar tu mapa de progresión'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(marcador, findsNothing);
      expect(experiencia.consultas, 1);

      experiencia.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(experiencia.consultas, 2);
      expect(
        find.text('No pudimos cargar tu mapa de progresión'),
        findsNothing,
      );
      expect(enTramo(2), findsOneWidget);
    });

    testWidgets('nunca muestra el mensaje técnico del error', (tester) async {
      final experiencia = ExperienciaFalsa(acumulada: 700)
        ..error = StateError('PostgrestException: permission denied');
      await _montar(
        tester,
        catalogo: niveles,
        repositorioExperiencia: experiencia,
      );

      expect(find.textContaining('PostgrestException'), findsNothing);
      expect(find.textContaining('permission denied'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    });

    testWidgets('si fallan los niveles también avisa y permite reintentar', (
      tester,
    ) async {
      final repositorio = NivelesFalso(catalogo: niveles)
        ..errorAlListar = StateError('sin conexión');
      await _montar(tester, repositorioNiveles: repositorio, experiencia: 700);

      expect(
        find.text('No pudimos cargar tu mapa de progresión'),
        findsOneWidget,
      );
      expect(find.textContaining('sin conexión'), findsNothing);

      repositorio.errorAlListar = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byType(CaminoProgresion), findsOneWidget);
      expect(enTramo(2), findsOneWidget);
    });
  });

  group('dice en palabras dónde está (criterio 1)', () {
    testWidgets('con progreso nombra el último nivel alcanzado', (
      tester,
    ) async {
      await _montar(tester, catalogo: niveles, experiencia: 700);

      expect(find.text('Vas en Plata'), findsOneWidget);
    });

    testWidgets('con 0 XP dice que está en el punto de partida', (
      tester,
    ) async {
      await _montar(tester, catalogo: niveles, experiencia: 0);

      expect(find.text('En el punto de partida'), findsOneWidget);
    });

    testWidgets('sin niveles también está en el punto de partida', (
      tester,
    ) async {
      await _montar(tester, catalogo: const [], experiencia: 300);

      expect(find.text('En el punto de partida'), findsOneWidget);
    });
  });

  test('la ruta de la pantalla es la de la pestaña Progreso (criterio 4)', () {
    // Si una cambia sin la otra, la pestaña llevaría a ninguna parte.
    expect(MapaProgresionScreen.ruta, SeccionPrincipal.progreso.ruta);
  });
}

/// Abre la pantalla del mapa con los datos que indique la prueba.
Future<void> _montar(
  WidgetTester tester, {
  List<Nivel> catalogo = const [],
  NivelesFalso? repositorioNiveles,
  int experiencia = 0,
  ExperienciaFalsa? repositorioExperiencia,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        nivelesRepositoryProvider.overrideWithValue(
          repositorioNiveles ?? NivelesFalso(catalogo: catalogo),
        ),
        experienciaRepositoryProvider.overrideWithValue(
          repositorioExperiencia ?? ExperienciaFalsa(acumulada: experiencia),
        ),
      ],
      child: const MaterialApp(home: MapaProgresionScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
