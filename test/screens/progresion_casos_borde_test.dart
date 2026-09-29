import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/screens/home/progresion_screen.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/widgets/barra_progresion.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';

/// Los casos borde de la progresión (SCRUM-189).
///
/// Los tres que nombra la historia —nivel más alto, sin niveles creados y sin
/// experiencia— más los datos raros que podrían llegar el día que exista el
/// motor de experiencia. En ninguno la pantalla puede fallar: un
/// desbordamiento de layout o una excepción hacen fallar la prueba por sí
/// solos.
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const niveles = [bronce, plata];

  // Anchos reales: el más estrecho que se sigue vendiendo, el Android común,
  // un iPhone actual, un teléfono grande y una tableta pequeña.
  const tamanos = {
    'estrecho': Size(320, 568),
    'común': Size(360, 640),
    'normal': Size(390, 844),
    'grande': Size(430, 932),
    'tableta': Size(768, 1024),
  };

  Future<void> montar(
    WidgetTester tester, {
    List<Nivel> catalogo = niveles,
    int experiencia = 0,
    Size tamano = const Size(390, 844),
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
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
            NivelesFalso(catalogo: catalogo),
          ),
          experienciaRepositoryProvider.overrideWithValue(
            ExperienciaFalsa(acumulada: experiencia),
          ),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String texto(WidgetTester tester, Key clave) =>
      tester.widget<Text>(find.byKey(clave)).data!;

  group('sin experiencia acumulada', () {
    testWidgets('dice que aún no tiene nivel y cuánto le falta para el '
        'primero', (tester) async {
      await montar(tester, experiencia: 0);

      expect(texto(tester, ProgresionScreen.claveNivelActual), 'Aún sin nivel');
      expect(
        texto(tester, ProgresionScreen.claveExperiencia),
        '0 XP acumulados',
      );
      expect(
        texto(tester, ProgresionScreen.claveFaltante),
        'Te faltan 100 XP para alcanzarlo.',
      );
    });

    testWidgets('la barra se dibuja vacía, no rota', (tester) async {
      await montar(tester, experiencia: 0);

      expect(
        tester
            .widget<LinearProgressIndicator>(find.byKey(BarraProgresion.clave))
            .value,
        0,
      );
      expect(find.text('0 de 100 XP'), findsOneWidget);
    });
  });

  group('en el nivel más alto', () {
    testWidgets('no promete un siguiente nivel que no existe', (tester) async {
      await montar(tester, experiencia: 900);

      expect(find.text('Estás en el nivel más alto'), findsOneWidget);
      expect(find.text('No hay ninguno por encima por ahora.'), findsOneWidget);
      expect(find.byKey(ProgresionScreen.claveFaltante), findsNothing);
      expect(find.byKey(BarraProgresion.clave), findsNothing);
    });

    testWidgets('con un único nivel creado también vale', (tester) async {
      await montar(tester, catalogo: const [bronce], experiencia: 150);

      expect(texto(tester, ProgresionScreen.claveNivelActual), 'Bronce');
      expect(find.text('Estás en el nivel más alto'), findsOneWidget);
    });

    testWidgets('justo al entrar al último nivel ya no hay siguiente', (
      tester,
    ) async {
      await montar(tester, experiencia: 500);

      expect(texto(tester, ProgresionScreen.claveNivelActual), 'Plata');
      expect(find.text('Estás en el nivel más alto'), findsOneWidget);
    });
  });

  group('sin niveles creados', () {
    testWidgets('avisa en vez de fallar', (tester) async {
      await montar(tester, catalogo: const [], experiencia: 0);

      expect(find.text('Todavía no hay niveles'), findsOneWidget);
      expect(
        find.text(
          'Cuando se configure la progresión, aquí verás cuánto te falta '
          'para el siguiente.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(ProgresionScreen.claveNivelActual), findsNothing);
      expect(find.byKey(BarraProgresion.clave), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tampoco falla si el corredor ya tenía experiencia', (
      tester,
    ) async {
      // Puede pasar: la XP se acredita por retos, que no dependen de que haya
      // niveles configurados.
      await montar(tester, catalogo: const [], experiencia: 4200);

      expect(find.text('Todavía no hay niveles'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('datos que no deberían llegar', () {
    testWidgets('una experiencia negativa no rompe la pantalla', (
      tester,
    ) async {
      // El contrato dice que nunca es negativa; si el motor se equivoca, se
      // ve el estado inicial, no una barra al revés.
      await montar(tester, experiencia: -50);

      expect(texto(tester, ProgresionScreen.claveNivelActual), 'Aún sin nivel');
      expect(
        tester
            .widget<LinearProgressIndicator>(find.byKey(BarraProgresion.clave))
            .value,
        0,
      );
      expect(find.text('0 de 100 XP'), findsOneWidget);
    });

    testWidgets('una experiencia enorme deja en el nivel más alto', (
      tester,
    ) async {
      await montar(tester, experiencia: 999999999);

      expect(texto(tester, ProgresionScreen.claveNivelActual), 'Plata');
      expect(find.text('Estás en el nivel más alto'), findsOneWidget);
    });

    testWidgets('un nombre de nivel larguísimo no desborda la tarjeta', (
      tester,
    ) async {
      await montar(
        tester,
        catalogo: const [
          Nivel(
            id: 'n-1',
            nombre: 'Corredor incansable de madrugadas interminables',
            umbralExperiencia: 100,
          ),
        ],
        experiencia: 0,
        tamano: tamanos['estrecho']!,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('en cualquier pantalla', () {
    for (final tamano in tamanos.entries) {
      testWidgets('ancho ${tamano.key}, con niveles y sin ellos', (
        tester,
      ) async {
        await montar(tester, experiencia: 300, tamano: tamano.value);
        expect(find.text('Tu progresión'), findsOneWidget);

        await montar(
          tester,
          catalogo: const [],
          experiencia: 0,
          tamano: tamano.value,
        );
        expect(find.text('Todavía no hay niveles'), findsOneWidget);
      });

      testWidgets('ancho ${tamano.key} con el texto del sistema grande', (
        tester,
      ) async {
        await montar(
          tester,
          experiencia: 300,
          tamano: tamano.value,
          escalaTexto: 1.3,
        );

        expect(find.text('Tu progresión'), findsOneWidget);
      });
    }
  });
}
