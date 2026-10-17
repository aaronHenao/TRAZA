import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/presentacion_traza.dart';
import 'package:traza/screens/auth/conocer_traza_screen.dart';
import 'package:traza/services/auth_service.dart';

/// Service falso: la pantalla solo le pregunta si hay sesión.
class _MockAuthService extends Mock implements AuthService {}

/// Pruebas de la pantalla de presentación (SCRUM-279).
///
/// De quién la abre y a dónde vuelve se encarga SCRUM-280; aquí solo se
/// comprueba que muestre el contenido y que entre en cualquier pantalla.
void main() {
  // Anchos reales: el más estrecho que se sigue vendiendo, el Android común,
  // un iPhone actual, un teléfono grande y una tableta pequeña.
  const tamanos = {
    'estrecho': Size(320, 568),
    'común': Size(360, 640),
    'normal': Size(390, 844),
    'grande': Size(430, 932),
    'tableta': Size(768, 1024),
  };

  testWidgets('muestra la identidad de la marca', (tester) async {
    await _montar(tester);

    expect(find.text(ConocerTrazaScreen.titulo), findsOneWidget);
    expect(find.text(PresentacionTraza.lema), findsOneWidget);
    expect(find.text(PresentacionTraza.queEs), findsOneWidget);
  });

  testWidgets('explica cómo funciona en tres pasos numerados', (tester) async {
    await _montar(tester);

    expect(find.text('CÓMO FUNCIONA'), findsOneWidget);
    for (final paso in PasoTraza.values) {
      await tester.scrollUntilVisible(find.text(paso.texto), 200);

      expect(find.text(paso.texto), findsOneWidget, reason: paso.name);
      expect(find.text('${paso.numero}'), findsOneWidget, reason: paso.name);
    }
  });

  testWidgets('los pasos van antes que la lista de funciones', (tester) async {
    // Primero cómo encaja todo y después el detalle: al revés hay que
    // deducir la gamificación de una lista.
    await _montar(tester, tamano: const Size(390, 1800));

    final pasos = tester.getTopLeft(find.text(PasoTraza.corres.texto)).dy;
    final funciones = tester
        .getTopLeft(find.text(FuncionTraza.registrar.titulo))
        .dy;

    expect(pasos, lessThan(funciones));
  });

  testWidgets('enumera las cinco funciones con su explicación', (tester) async {
    await _montar(tester);

    for (final funcion in FuncionTraza.values) {
      // La lista es más larga que la pantalla: se recorre como lo haría el
      // usuario.
      await tester.scrollUntilVisible(find.text(funcion.titulo), 200);

      expect(find.text(funcion.titulo), findsOneWidget, reason: funcion.name);
      expect(find.text(funcion.detalle), findsOneWidget, reason: funcion.name);
    }
  });

  testWidgets('cada función se dibuja con su propio icono', (tester) async {
    // En una pantalla alta caben todas a la vez y se pueden comparar.
    await _montar(tester, tamano: const Size(390, 1800));

    final iconos = tester
        .widgetList<TarjetaFuncion>(find.byType(TarjetaFuncion))
        .map((tarjeta) => tarjeta.icono)
        .toList();

    expect(iconos, hasLength(FuncionTraza.values.length));
    // Ninguna se queda con el genérico ni repite el de otra.
    expect(iconos, isNot(contains(Icons.circle_outlined)));
    expect(iconos.toSet(), hasLength(iconos.length));
  });

  testWidgets('sin sesión invita a crear la cuenta', (tester) async {
    await _montar(tester, tamano: const Size(390, 1800));

    expect(find.byKey(ConocerTrazaScreen.claveCrearCuenta), findsOneWidget);
    expect(find.text(PresentacionTraza.invitacion), findsOneWidget);
  });

  testWidgets('con sesión no invita a nada', (tester) async {
    // A quien ya tiene cuenta, ofrecerle crearla no le dice nada.
    await _montar(tester, tamano: const Size(390, 1800), haySesion: true);

    expect(
      find.byKey(ConocerTrazaScreen.claveCrearCuenta, skipOffstage: false),
      findsNothing,
    );
    expect(find.text(PresentacionTraza.invitacion), findsNothing);
  });

  testWidgets('no ofrece iniciar sesión: no reemplaza al login', (
    tester,
  ) async {
    await _montar(tester, tamano: const Size(390, 1800));

    expect(find.textContaining('Iniciar sesión'), findsNothing);
    expect(find.textContaining('Regístrate'), findsNothing);
  });

  testWidgets('abierta de frente no ofrece volver', (tester) async {
    // Sin nada detrás, una flecha de retroceso no llevaría a ninguna parte.
    await _montar(tester);

    expect(find.byTooltip('Volver'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('entra en cualquier pantalla', () {
    for (final tamano in tamanos.entries) {
      testWidgets('ancho ${tamano.key}', (tester) async {
        await _montar(tester, tamano: tamano.value);

        expect(find.text(ConocerTrazaScreen.titulo), findsOneWidget);
      });

      testWidgets('ancho ${tamano.key} con el texto del sistema grande', (
        tester,
      ) async {
        await _montar(tester, tamano: tamano.value, escalaTexto: 1.3);

        expect(find.text(ConocerTrazaScreen.titulo), findsOneWidget);
      });
    }
  });
}

/// Abre la presentación como única pantalla: aquí no se navega a ninguna
/// parte, pero lleva router porque la pantalla pregunta si hay a dónde volver,
/// y service de autenticación porque pregunta si hay sesión.
Future<void> _montar(
  WidgetTester tester, {
  Size tamano = const Size(390, 844),
  double escalaTexto = 1,
  bool haySesion = false,
}) async {
  final auth = _MockAuthService();
  when(() => auth.haySesion).thenReturn(haySesion);

  tester.view.physicalSize = tamano * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const ConocerTrazaScreen())],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
        child: MaterialApp.router(routerConfig: router),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
