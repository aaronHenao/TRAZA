import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/widgets/miniatura_ruta.dart';

/// Pruebas de la miniatura de una ruta (SCRUM-247).
void main() {
  const recuadro = Size(76, 76);
  const margen = MiniaturaRuta.margen;

  PuntoRuta p(double latitud, double longitud) =>
      PuntoRuta(latitud: latitud, longitud: longitud);

  group('cómo lleva la ruta al recuadro', () {
    test('sin puntos no hay nada que dibujar', () {
      expect(MiniaturaRuta.proyectar(const [], recuadro), isEmpty);
    });

    test('todo queda dentro del recuadro, sin tocar el margen', () {
      final puntos = [
        p(6.2442, -75.5812),
        p(6.2470, -75.5790),
        p(6.2500, -75.5830),
        p(6.2455, -75.5860),
      ];

      for (final punto in MiniaturaRuta.proyectar(puntos, recuadro)) {
        expect(punto.dx, inInclusiveRange(margen, recuadro.width - margen));
        expect(punto.dy, inInclusiveRange(margen, recuadro.height - margen));
      }
    });

    test('el norte queda arriba', () {
      final enPantalla = MiniaturaRuta.proyectar([
        p(6.24, -75.58), // sur
        p(6.25, -75.58), // norte
      ], recuadro);

      expect(enPantalla[1].dy, lessThan(enPantalla[0].dy));
    });

    test('el oriente queda a la derecha', () {
      final enPantalla = MiniaturaRuta.proyectar([
        p(6.24, -75.59), // occidente
        p(6.24, -75.58), // oriente
      ], recuadro);

      expect(enPantalla[1].dx, greaterThan(enPantalla[0].dx));
    });

    test('no deforma la ruta: una línea de norte a sur sale vertical y '
        'centrada', () {
      final enPantalla = MiniaturaRuta.proyectar([
        p(6.24, -75.58),
        p(6.25, -75.58),
      ], recuadro);

      // Misma x para los dos, en el centro: no se estira a lo ancho para
      // llenar el recuadro.
      expect(enPantalla[0].dx, enPantalla[1].dx);
      expect(enPantalla[0].dx, closeTo(recuadro.width / 2, 0.001));
      // Y de margen a margen a lo alto, que es lo que manda.
      expect(enPantalla[1].dy, closeTo(margen, 0.001));
      expect(enPantalla[0].dy, closeTo(recuadro.height - margen, 0.001));
    });

    test('la longitud se encoge lejos del ecuador', () {
      // Un "cuadrado" de un grado por lado a 60° de latitud: allá un grado
      // de longitud mide la mitad que uno de latitud, así que la ruta sale
      // el doble de alta que de ancha.
      final enPantalla = MiniaturaRuta.proyectar([
        p(60, 10),
        p(61, 11),
      ], recuadro);

      final ancho = (enPantalla[1].dx - enPantalla[0].dx).abs();
      final alto = (enPantalla[1].dy - enPantalla[0].dy).abs();
      expect(ancho / alto, closeTo(0.5, 0.01));
    });

    test('todos los puntos en el mismo lugar quedan en el centro', () {
      final enPantalla = MiniaturaRuta.proyectar([
        p(6.24, -75.58),
        p(6.24, -75.58),
      ], recuadro);

      for (final punto in enPantalla) {
        expect(punto, recuadro.center(Offset.zero));
      }
    });

    test('se adapta a un recuadro ancho, como el de la tarjeta compacta', () {
      const ancho = Size(158, 64);
      final puntos = [p(6.24, -75.60), p(6.25, -75.58), p(6.24, -75.56)];

      for (final punto in MiniaturaRuta.proyectar(puntos, ancho)) {
        expect(punto.dx, inInclusiveRange(margen, ancho.width - margen));
        expect(punto.dy, inInclusiveRange(margen, ancho.height - margen));
      }
    });
  });

  group('lo que se ve', () {
    Future<void> montar(WidgetTester tester, List<PuntoRuta> puntos) {
      return tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox.fromSize(
              size: recuadro,
              child: MiniaturaRuta(puntos: puntos),
            ),
          ),
        ),
      );
    }

    testWidgets('con forma, dibuja el recorrido', (tester) async {
      await montar(tester, [p(6.24, -75.58), p(6.25, -75.57)]);

      expect(
        find.descendant(
          of: find.byType(MiniaturaRuta),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
      expect(find.byKey(MiniaturaRuta.claveSinForma), findsNothing);
    });

    testWidgets('sin puntos, el icono de ruta', (tester) async {
      await montar(tester, const []);

      expect(find.byKey(MiniaturaRuta.claveSinForma), findsOneWidget);
    });

    testWidgets('con un solo lugar tampoco hay forma: el icono', (
      tester,
    ) async {
      await montar(tester, [p(6.24, -75.58), p(6.24, -75.58)]);

      expect(find.byKey(MiniaturaRuta.claveSinForma), findsOneWidget);
    });

    testWidgets('no se vuelve a pintar si la forma es la misma (SCRUM-251)', (
      tester,
    ) async {
      CustomPainter pintor() => tester
          .widgetList<CustomPaint>(
            find.descendant(
              of: find.byType(MiniaturaRuta),
              matching: find.byType(CustomPaint),
            ),
          )
          .map((pintura) => pintura.painter)
          .whereType<CustomPainter>()
          .single;

      await montar(tester, [p(6.24, -75.58), p(6.25, -75.57)]);
      final antes = pintor();

      // Los mismos puntos en una lista nueva, como llegan al recargar: al
      // desplazar el carrusel no hay por qué volver a dibujarla.
      await montar(tester, [p(6.24, -75.58), p(6.25, -75.57)]);
      expect(pintor().shouldRepaint(antes), isFalse);

      final igual = pintor();
      await montar(tester, [p(6.24, -75.58), p(6.26, -75.56)]);
      expect(pintor().shouldRepaint(igual), isTrue);
    });

    testWidgets('un lector de pantalla no la anuncia', (tester) async {
      // El nombre y los datos de la ruta ya van en texto al lado.
      final semantica = tester.ensureSemantics();
      await montar(tester, [p(6.24, -75.58), p(6.25, -75.57)]);

      expect(
        find.descendant(
          of: find.byType(MiniaturaRuta),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });
}
