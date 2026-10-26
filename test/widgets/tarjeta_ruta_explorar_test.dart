import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/widgets/miniatura_ruta.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/rutas_repository_falso.dart';

/// Pruebas de la tarjeta de ruta de Explorar rutas y del carrusel de la
/// portada (SCRUM-247).
///
/// Es el criterio 2 de HU-29: la miniatura, el nombre, la dificultad, la
/// distancia, el desnivel y quién la creó, en las dos disposiciones.
void main() {
  final vuelta = rutaDePrueba(
    id: 'r-1',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.publicada,
    miniatura: const [
      PuntoRuta(latitud: 6.2566, longitud: -75.5900),
      PuntoRuta(latitud: 6.2580, longitud: -75.5885),
      PuntoRuta(latitud: 6.2566, longitud: -75.5870),
    ],
    fechaPublicacion: DateTime(2026, 10, 18, 9),
  );

  const nombreLargo =
      'Vuelta completa al estadio Atanasio Girardot pasando por el '
      'coliseo, la unidad deportiva y regreso por la avenida';

  /// Las dos disposiciones, para correr las mismas pruebas en las dos.
  final disposiciones = {
    'de lado': (Ruta ruta, VoidCallback? onTap) =>
        TarjetaRutaExplorar(ruta: ruta, onTap: onTap),
    'compacta': (Ruta ruta, VoidCallback? onTap) =>
        TarjetaRutaExplorar.compacta(ruta: ruta, onTap: onTap),
  };

  Future<void> montar(
    WidgetTester tester,
    Widget tarjeta, {
    Size tamano = const Size(390, 844),
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final compacta = tarjeta is TarjetaRutaExplorar && tarjeta.compacta;
    // Como la montan la lista y el carrusel: la de lado a todo el ancho, y la
    // compacta en el alto que le da el carrusel.
    final escala = escalaTexto.clamp(1.0, 1.6);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topLeft,
                child: compacta
                    ? SizedBox(
                        height: TarjetaRutaExplorar.altoCompacta * escala,
                        child: tarjeta,
                      )
                    : tarjeta,
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final MapEntry(key: nombre, value: crear) in disposiciones.entries) {
    group(nombre, () {
      testWidgets('muestra la miniatura, el nombre y quién la creó', (
        tester,
      ) async {
        await montar(tester, crear(vuelta, null));

        final miniatura = tester.widget<MiniaturaRuta>(
          find.byType(MiniaturaRuta),
        );
        expect(miniatura.puntos, vuelta.miniatura);
        expect(find.text('Vuelta al estadio'), findsOneWidget);
        expect(find.text('Por Ana'), findsOneWidget);
      });

      testWidgets('muestra la distancia, la dificultad y el desnivel', (
        tester,
      ) async {
        await montar(tester, crear(vuelta, null));

        expect(find.text('5.23 km'), findsOneWidget);
        // Sin dificultad asignada (SCRUM-363) ni desnivel, la tarjeta lo
        // dice en vez de dejar el hueco o inventarse algo.
        expect(find.text(TarjetaRutaExplorar.sinDificultad), findsOneWidget);
        expect(find.text(TarjetaRutaExplorar.sinDesnivel), findsOneWidget);
      });

      testWidgets('con dificultad asignada, la pastilla la dice (SCRUM-275)', (
        tester,
      ) async {
        final clasificada = rutaDePrueba(
          estado: EstadoRuta.publicada,
          dificultad: Dificultad.moderada,
        );

        await montar(tester, crear(clasificada, null));

        expect(find.text('Moderada'), findsOneWidget);
        expect(find.text(TarjetaRutaExplorar.sinDificultad), findsNothing);
      });

      testWidgets('sin distancia lo dice como el resto de la app', (
        tester,
      ) async {
        final sinDistancia = rutaDePrueba(
          estado: EstadoRuta.publicada,
          distanciaKm: null,
        );

        await montar(tester, crear(sinDistancia, null));

        expect(find.text(TarjetaRuta.sinDistancia), findsOneWidget);
      });

      testWidgets('sin miniatura muestra el icono de ruta', (tester) async {
        await montar(
          tester,
          crear(rutaDePrueba(estado: EstadoRuta.publicada), null),
        );

        expect(find.byKey(MiniaturaRuta.claveSinForma), findsOneWidget);
      });

      testWidgets('se puede tocar cuando hay a dónde ir', (tester) async {
        var toques = 0;
        await montar(tester, crear(vuelta, () => toques++));

        await tester.tap(find.text('Vuelta al estadio'));
        await tester.pump();

        expect(toques, 1);
      });

      testWidgets('en la pantalla más estrecha, con un nombre larguísimo, '
          'no desborda', (tester) async {
        await montar(
          tester,
          crear(
            rutaDePrueba(estado: EstadoRuta.publicada, nombre: nombreLargo),
            null,
          ),
          tamano: const Size(320, 568),
        );

        expect(tester.takeException(), isNull);
      });

      for (final escala in [1.3, 1.6]) {
        testWidgets('con el texto del sistema a ${(escala * 100).round()}% '
            'tampoco', (tester) async {
          await montar(
            tester,
            crear(
              rutaDePrueba(estado: EstadoRuta.publicada, nombre: nombreLargo),
              null,
            ),
            tamano: const Size(320, 568),
            escalaTexto: escala,
          );

          expect(tester.takeException(), isNull);
          expect(find.text(TarjetaRutaExplorar.sinDificultad), findsOneWidget);
        });
      }
    });
  }

  group('cada disposición en su sitio', () {
    testWidgets('la de lado lleva el nombre en dos líneas como mucho', (
      tester,
    ) async {
      await montar(
        tester,
        TarjetaRutaExplorar(
          ruta: rutaDePrueba(estado: EstadoRuta.publicada, nombre: nombreLargo),
        ),
      );

      expect(tester.widget<Text>(find.text(nombreLargo)).maxLines, 2);
    });

    testWidgets('la compacta, en una sola, para que todas midan lo mismo', (
      tester,
    ) async {
      await montar(
        tester,
        TarjetaRutaExplorar.compacta(
          ruta: rutaDePrueba(estado: EstadoRuta.publicada, nombre: nombreLargo),
        ),
      );

      expect(tester.widget<Text>(find.text(nombreLargo)).maxLines, 1);
    });

    testWidgets('la compacta tiene el ancho fijo del carrusel', (tester) async {
      await montar(tester, TarjetaRutaExplorar.compacta(ruta: vuelta));

      expect(
        tester.getSize(find.byType(TarjetaRutaExplorar)).width,
        TarjetaRutaExplorar.anchoCompacta,
      );
    });

    testWidgets('la de lado lleva la miniatura cuadrada a la izquierda', (
      tester,
    ) async {
      await montar(tester, TarjetaRutaExplorar(ruta: vuelta));

      final miniatura = tester.getRect(find.byType(MiniaturaRuta));
      expect(miniatura.width, TarjetaRutaExplorar.ladoMiniatura);
      expect(miniatura.height, TarjetaRutaExplorar.ladoMiniatura);
      expect(
        miniatura.right,
        lessThan(tester.getTopLeft(find.text('Vuelta al estadio')).dx),
      );
    });

    testWidgets('la compacta lleva la miniatura arriba, a todo el ancho', (
      tester,
    ) async {
      await montar(tester, TarjetaRutaExplorar.compacta(ruta: vuelta));

      final miniatura = tester.getRect(find.byType(MiniaturaRuta));
      expect(miniatura.height, TarjetaRutaExplorar.altoMiniaturaCompacta);
      expect(
        miniatura.bottom,
        lessThan(tester.getTopLeft(find.text('Vuelta al estadio')).dy),
      );
    });
  });
}
