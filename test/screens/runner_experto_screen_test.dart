import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/runner_experto.dart';
import 'package:traza/screens/home/runner_experto_screen.dart';
import 'package:traza/services/auth_service.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/experiencia_falsa.dart';

class _MockAuthService extends Mock implements AuthService {}

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
      fechaRegistro: DateTime(2026, 7, 1),
      ahora: hoy,
    );

    expect(texto(tester, RunnerExpertoScreen.claveEstado), 'Bloqueado');
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
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

  testWidgets('los requisitos dicen la meta: 150.000 XP y 6 meses', (
    tester,
  ) async {
    await _montar(tester, experiencia: 0, fechaRegistro: antiguo, ahora: hoy);

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

  testWidgets('con los dos requisitos queda desbloqueado, sin candado', (
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
        relojProvider.overrideWithValue(() => ahora),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
