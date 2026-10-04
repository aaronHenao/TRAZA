import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/mapa_progresion.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/widgets/camino_progresion.dart';

/// Pruebas del dibujo del camino del mapa de progresión (SCRUM-226).
///
/// El marcador "Tú" vive dentro del tramo que el usuario está recorriendo, o
/// dentro de la parada donde está si ya no hay tramo por delante.
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const oro = Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500);
  const niveles = [bronce, plata, oro];

  Future<void> montar(
    WidgetTester tester,
    int experiencia, {
    List<Nivel> catalogo = niveles,
  }) async {
    // El camino no se desplaza solo: la pantalla lo mete en su lista. Aquí
    // hace lo mismo un SingleChildScrollView.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CaminoProgresion(
              mapa: MapaProgresion.calcular(
                experiencia: experiencia,
                niveles: catalogo,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder parada(int indice) => find.byKey(ValueKey('parada-$indice'));
  Finder tramo(int indice) => find.byKey(ValueKey('tramo-$indice'));
  final marcador = find.byKey(CaminoProgresion.claveMarcador);

  Finder dentroDe(Finder contenedor, Finder buscado) =>
      find.descendant(of: contenedor, matching: buscado);

  testWidgets('dibuja una parada por cada punto del camino y un tramo entre '
      'cada par', (tester) async {
    await montar(tester, 700);

    for (var i = 0; i < 4; i++) {
      expect(parada(i), findsOneWidget);
    }
    expect(parada(4), findsNothing);
    for (var i = 0; i < 3; i++) {
      expect(tramo(i), findsOneWidget);
    }
    expect(tramo(3), findsNothing);
  });

  testWidgets('cada parada muestra su nombre y los niveles su umbral', (
    tester,
  ) async {
    await montar(tester, 700);

    expect(dentroDe(parada(0), find.text('Inicio')), findsOneWidget);
    expect(dentroDe(parada(1), find.text('Bronce')), findsOneWidget);
    expect(dentroDe(parada(1), find.text('100 XP')), findsOneWidget);
    expect(dentroDe(parada(2), find.text('Plata')), findsOneWidget);
    expect(dentroDe(parada(2), find.text('500 XP')), findsOneWidget);
    expect(dentroDe(parada(3), find.text('Oro')), findsOneWidget);
    expect(dentroDe(parada(3), find.text('1500 XP')), findsOneWidget);
  });

  group('el marcador "Tú"', () {
    testWidgets('criterio 1: con progreso, está en el tramo que va '
        'recorriendo', (tester) async {
      // 700 XP: pasó Plata (parada 2) y va hacia Oro, por el tramo 2.
      await montar(tester, 700);

      expect(dentroDe(tramo(2), marcador), findsOneWidget);
      expect(dentroDe(tramo(0), marcador), findsNothing);
      expect(dentroDe(tramo(1), marcador), findsNothing);
      expect(dentroDe(marcador, find.text('Tú')), findsOneWidget);
    });

    testWidgets('criterio 2: con 0 XP, está al comienzo, en el primer '
        'tramo', (tester) async {
      await montar(tester, 0);

      expect(dentroDe(tramo(0), marcador), findsOneWidget);
      expect(dentroDe(tramo(1), marcador), findsNothing);
    });

    testWidgets('con la experiencia exacta de un nivel ya está en el tramo '
        'que sale de él', (tester) async {
      await montar(tester, 500);

      expect(dentroDe(tramo(2), marcador), findsOneWidget);
      expect(dentroDe(tramo(1), marcador), findsNothing);
    });

    testWidgets('en el nivel más alto está sobre la última parada', (
      tester,
    ) async {
      await montar(tester, 2000);

      expect(dentroDe(parada(3), marcador), findsOneWidget);
      expect(dentroDe(tramo(2), marcador), findsNothing);
    });

    testWidgets('sin niveles está sobre la parada inicial', (tester) async {
      await montar(tester, 300, catalogo: const []);

      expect(parada(0), findsOneWidget);
      expect(parada(1), findsNothing);
      expect(tramo(0), findsNothing);
      expect(dentroDe(parada(0), find.text('Inicio')), findsOneWidget);
      expect(dentroDe(parada(0), marcador), findsOneWidget);
    });

    testWidgets('hay uno solo, esté donde esté', (tester) async {
      for (final experiencia in [0, 700, 2000]) {
        await montar(tester, experiencia);

        expect(marcador, findsOneWidget, reason: 'con $experiencia XP');
        expect(find.text('Tú'), findsOneWidget, reason: 'con $experiencia XP');
      }
    });
  });

  group('iconos de las paradas', () {
    testWidgets('la inicial lleva bandera, las alcanzadas check y las '
        'pendientes candado', (tester) async {
      // 700 XP: Bronce y Plata alcanzadas, Oro pendiente.
      await montar(tester, 700);

      expect(dentroDe(parada(0), find.byIcon(Icons.flag)), findsOneWidget);
      expect(
        dentroDe(parada(0), find.byIcon(Icons.lock_outline)),
        findsNothing,
      );

      for (final alcanzada in [1, 2]) {
        expect(
          dentroDe(parada(alcanzada), find.byIcon(Icons.check_circle)),
          findsOneWidget,
        );
        expect(
          dentroDe(parada(alcanzada), find.byIcon(Icons.lock_outline)),
          findsNothing,
        );
      }

      expect(
        dentroDe(parada(3), find.byIcon(Icons.lock_outline)),
        findsOneWidget,
      );
      expect(
        dentroDe(parada(3), find.byIcon(Icons.check_circle)),
        findsNothing,
      );
    });

    testWidgets('con 0 XP todos los niveles están pendientes', (tester) async {
      await montar(tester, 0);

      for (final pendiente in [1, 2, 3]) {
        expect(
          dentroDe(parada(pendiente), find.byIcon(Icons.lock_outline)),
          findsOneWidget,
        );
      }
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('al llegar a un umbral exacto, ese nivel ya sale alcanzado', (
      tester,
    ) async {
      await montar(tester, 100);

      expect(
        dentroDe(parada(1), find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
    });
  });

  group('pantalla estrecha', () {
    const largos = [
      Nivel(
        id: 'l-1',
        nombre: 'Corredor principiante de barrio',
        umbralExperiencia: 50,
      ),
      Nivel(
        id: 'l-2',
        nombre: 'Trotador constante de fin de semana',
        umbralExperiencia: 150,
      ),
      Nivel(
        id: 'l-3',
        nombre: 'Explorador de rutas urbanas nocturnas',
        umbralExperiencia: 400,
      ),
      Nivel(
        id: 'l-4',
        nombre: 'Fondista de montaña y sendero largo',
        umbralExperiencia: 900,
      ),
      Nivel(
        id: 'l-5',
        nombre: 'Medio maratonista incansable del valle',
        umbralExperiencia: 2000,
      ),
      Nivel(
        id: 'l-6',
        nombre: 'Maratonista de élite de la ciudad de Medellín',
        umbralExperiencia: 5000,
      ),
      Nivel(
        id: 'l-7',
        nombre: 'Ultrafondista de cordillera y páramo',
        umbralExperiencia: 12000,
      ),
      Nivel(
        id: 'l-8',
        nombre: 'Leyenda absoluta del asfalto antioqueño',
        umbralExperiencia: 100000,
      ),
    ];

    for (final experiencia in [0, 1000, 200000]) {
      testWidgets('8 niveles de nombres largos no desbordan en 320x568 '
          '($experiencia XP)', (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 568 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await montar(tester, experiencia, catalogo: largos);

        expect(tester.takeException(), isNull);
        expect(parada(8), findsOneWidget);
        expect(marcador, findsOneWidget);
      });
    }
  });
}
