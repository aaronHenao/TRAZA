import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/runner_experto.dart';
import 'package:traza/screens/home/runner_experto_screen.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';

class _MockAuthService extends Mock implements AuthService {}

/// Un mapa de [cantidad] niveles, el primero en [paso] XP y cada uno [paso]
/// más arriba que el anterior.
List<Nivel> _mapa(int cantidad, {int paso = 100}) => [
  for (var i = 1; i <= cantidad; i++)
    Nivel(id: 'n$i', nombre: 'Etapa $i', umbralExperiencia: i * paso),
];

/// Pruebas de la pantalla de Runner Experto (SCRUM-212 a SCRUM-215).
void main() {
  final hoy = DateTime(2026, 9, 28, 18);
  final antiguo = DateTime(2025, 1, 10);

  String texto(WidgetTester tester, Key clave) {
    final textos = tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(clave), matching: find.byType(Text)),
        )
        .map((t) => t.data);
    return textos.join(' | ');
  }

  testWidgets('bloqueado: muestra el candado y cuánto falta en cada '
      'requisito', (tester) async {
    await _montar(
      tester,
      experiencia: 1250,
      niveles: _mapa(11, paso: 1000),
      fechaRegistro: DateTime(2026, 7, 1),
      ahora: hoy,
    );

    expect(texto(tester, RunnerExpertoScreen.claveEstado), 'Bloqueado');
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(
      texto(tester, RunnerExpertoScreen.claveNiveles),
      contains('Vas en el nivel 1, Etapa 1. Te faltan 10 niveles.'),
    );
    expect(
      texto(tester, RunnerExpertoScreen.claveExperiencia),
      contains('Llevas 1.250 XP. Te faltan 148.750 XP.'),
    );
    expect(
      texto(tester, RunnerExpertoScreen.claveAntiguedad),
      contains(
        'Usas TRAZA desde el 1 de julio de 2026. Lo cumples el 1 de enero de '
        '2027 (faltan 95 días).',
      ),
    );
  });

  testWidgets('los requisitos dicen la meta: nivel 10, 150.000 XP y 6 meses', (
    tester,
  ) async {
    await _montar(tester, experiencia: 0, fechaRegistro: antiguo, ahora: hoy);

    expect(find.text('Superar el nivel 10 del mapa'), findsOneWidget);
    expect(find.text('150.000 XP acumulados'), findsOneWidget);
    expect(find.text('6 meses usando TRAZA'), findsOneWidget);
  });

  testWidgets('con un requisito cumplido lo marca y el rol sigue bloqueado', (
    tester,
  ) async {
    await _montar(tester, experiencia: 10, fechaRegistro: antiguo, ahora: hoy);

    expect(
      texto(tester, RunnerExpertoScreen.claveAntiguedad),
      contains('Cumplido: usas TRAZA desde el 10 de enero de 2025.'),
    );
    expect(texto(tester, RunnerExpertoScreen.claveEstado), 'Bloqueado');
  });

  testWidgets('con la XP y la antigüedad pero sin superar el nivel 10 sigue '
      'bloqueado', (tester) async {
    await _montar(
      tester,
      experiencia: 150000,
      niveles: _mapa(11, paso: 15000),
      fechaRegistro: antiguo,
      ahora: hoy,
    );

    expect(texto(tester, RunnerExpertoScreen.claveEstado), 'Bloqueado');
    expect(
      texto(tester, RunnerExpertoScreen.claveNiveles),
      contains('Vas en el nivel 10, Etapa 10. Te falta 1 nivel.'),
    );
    expect(
      find.text('Cumple los tres requisitos para desbloquear el rol.'),
      findsOneWidget,
    );
  });

  group('requisito de niveles (SCRUM-227)', () {
    testWidgets('sin ningún nivel alcanzado le faltan los 11', (tester) async {
      await _montar(
        tester,
        experiencia: 50,
        fechaRegistro: antiguo,
        ahora: hoy,
      );

      expect(
        texto(tester, RunnerExpertoScreen.claveNiveles),
        contains('Aún no alcanzas el primer nivel. Te faltan 11 niveles.'),
      );
    });

    testWidgets('si el mapa no llega a 11 niveles lo avisa', (tester) async {
      await _montar(
        tester,
        experiencia: 450,
        niveles: _mapa(8),
        fechaRegistro: antiguo,
        ahora: hoy,
      );

      expect(
        texto(tester, RunnerExpertoScreen.claveNiveles),
        contains(
          'Vas en el nivel 4, Etapa 4. Te faltan 7 niveles. Por ahora el '
          'mapa tiene 8 niveles.',
        ),
      );
    });

    testWidgets('sin niveles en el mapa lo dice', (tester) async {
      await _montar(
        tester,
        experiencia: 450,
        niveles: const [],
        fechaRegistro: antiguo,
        ahora: hoy,
      );

      expect(
        texto(tester, RunnerExpertoScreen.claveNiveles),
        contains(
          'Aún no alcanzas el primer nivel. Te faltan 11 niveles. Por ahora '
          'el mapa no tiene niveles.',
        ),
      );
    });
  });

  testWidgets('con los tres requisitos queda desbloqueado, sin candado', (
    tester,
  ) async {
    await _montar(
      tester,
      experiencia: 150000,
      fechaRegistro: antiguo,
      ahora: hoy,
    );

    expect(texto(tester, RunnerExpertoScreen.claveEstado), 'Desbloqueado');
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
    expect(
      texto(tester, RunnerExpertoScreen.claveNiveles),
      contains('Cumplido: vas en el nivel 11, Etapa 11.'),
    );
    expect(
      texto(tester, RunnerExpertoScreen.claveExperiencia),
      contains('Cumplido: tienes 150.000 XP.'),
    );
  });

  testWidgets('lista las ventajas del rol (SCRUM-213)', (tester) async {
    await _montar(tester, experiencia: 0, fechaRegistro: antiguo, ahora: hoy);

    for (final ventaja in VentajaRunnerExperto.values) {
      expect(find.text(ventaja.titulo), findsOneWidget);
      expect(find.text(ventaja.detalle), findsOneWidget);
    }
  });

  group('carga y error (SCRUM-215)', () {
    testWidgets('si la XP no carga, lo dice y deja reintentar', (tester) async {
      final experiencia = ExperienciaFalsa(acumulada: 500)
        ..error = Exception('sin red');
      await _montar(
        tester,
        repositorio: experiencia,
        fechaRegistro: antiguo,
        ahora: hoy,
      );

      expect(find.text('No pudimos cargar tu estado'), findsOneWidget);

      experiencia.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar tu estado'), findsNothing);
      expect(
        texto(tester, RunnerExpertoScreen.claveExperiencia),
        contains('Llevas 500 XP.'),
      );
    });

    testWidgets('si los niveles no cargan, lo dice y deja reintentar', (
      tester,
    ) async {
      final niveles = NivelesFalso(catalogo: _mapa(11))
        ..errorAlListar = Exception('sin red');
      await _montar(
        tester,
        experiencia: 450,
        repositorioNiveles: niveles,
        fechaRegistro: antiguo,
        ahora: hoy,
      );

      expect(find.text('No pudimos cargar tu estado'), findsOneWidget);

      niveles.errorAlListar = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(
        texto(tester, RunnerExpertoScreen.claveNiveles),
        contains('Vas en el nivel 4, Etapa 4.'),
      );
    });

    testWidgets('sin sesión no inventa una fecha: muestra el error', (
      tester,
    ) async {
      await _montar(tester, experiencia: 0, fechaRegistro: null, ahora: hoy);

      expect(find.text('No pudimos cargar tu estado'), findsOneWidget);
    });
  });

  group('formatos', () {
    test('las cifras llevan punto de miles', () {
      expect(formatearMiles(0), '0');
      expect(formatearMiles(999), '999');
      expect(formatearMiles(1250), '1.250');
      expect(formatearMiles(150000), '150.000');
      expect(formatearMiles(1234567), '1.234.567');
    });

    test('las fechas van con el mes en letras', () {
      expect(formatearFecha(DateTime(2027, 3, 28)), '28 de marzo de 2027');
    });
  });
}

Future<void> _montar(
  WidgetTester tester, {
  required DateTime? fechaRegistro,
  required DateTime ahora,
  int experiencia = 0,
  ExperienciaFalsa? repositorio,
  List<Nivel>? niveles,
  NivelesFalso? repositorioNiveles,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = _MockAuthService();
  when(() => auth.fechaCreacionCuenta).thenReturn(fechaRegistro);

  final router = GoRouter(
    initialLocation: RunnerExpertoScreen.ruta,
    routes: [
      GoRoute(
        path: RunnerExpertoScreen.ruta,
        builder: (_, _) => const RunnerExpertoScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        experienciaRepositoryProvider.overrideWithValue(
          repositorio ?? ExperienciaFalsa(acumulada: experiencia),
        ),
        // Por defecto, once niveles que se alcanzan con 1.100 XP: no
        // estorban cuando la prueba mira otro requisito.
        nivelesRepositoryProvider.overrideWithValue(
          repositorioNiveles ?? NivelesFalso(catalogo: niveles ?? _mapa(11)),
        ),
        relojProvider.overrideWithValue(() => ahora),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
