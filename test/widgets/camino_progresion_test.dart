import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/mapa_progresion.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_oficial.dart';
import 'package:traza/widgets/camino_progresion.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/rutas_repository_falso.dart';

/// Pruebas del dibujo del camino del mapa de progresión (rutas oficiales,
/// etapa 2).
///
/// Las paradas ya no son niveles con su XP: son las rutas oficiales, cada una
/// con su distancia, su dificultad y su estado. El marcador "Tú" vive dentro
/// de la parada siguiente, o de la última si el camino está terminado.
void main() {
  final estadio = rutaDePrueba(
    id: 'ruta-estadio',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.publicada,
    distanciaKm: 5.23,
    dificultad: Dificultad.facil,
  );
  final nutibara = rutaDePrueba(
    id: 'ruta-nutibara',
    nombre: 'Cerro Nutibara',
    estado: EstadoRuta.publicada,
    distanciaKm: 7.5,
    dificultad: Dificultad.dificil,
  );
  // Sin dificultad: un Runner Experto todavía no la clasificó.
  final rio = rutaDePrueba(
    id: 'ruta-rio',
    nombre: 'Parque del río',
    estado: EstadoRuta.publicada,
    distanciaKm: 3,
  );
  // Sin distancia: el entrenamiento del que salió no la guardó.
  final laureles = rutaDePrueba(
    id: 'ruta-laureles',
    nombre: 'Ciclovía de Laureles',
    estado: EstadoRuta.publicada,
    distanciaKm: null,
    dificultad: Dificultad.moderada,
  );

  List<RutaOficial> enOrden(List<Ruta> rutas) => [
    for (final (i, ruta) in rutas.indexed)
      RutaOficial(posicion: i + 1, ruta: ruta),
  ];

  final camino = enOrden([estadio, nutibara, rio]);

  Future<void> montar(
    WidgetTester tester, {
    Set<String> completadas = const {},
    List<RutaOficial>? oficiales,
    void Function(Ruta ruta)? onTapRuta,
  }) async {
    // El camino no se desplaza solo: la pantalla lo mete en su lista. Aquí
    // hace lo mismo un SingleChildScrollView.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CaminoProgresion(
              mapa: MapaProgresion.calcular(
                oficiales: oficiales ?? camino,
                completadas: completadas,
              ),
              onTapRuta: onTapRuta,
            ),
          ),
        ),
      ),
    );
  }

  Finder parada(String rutaId) =>
      find.byKey(CaminoProgresion.claveParada(rutaId));
  final marcador = find.byKey(CaminoProgresion.claveMarcador);

  Finder dentroDe(Finder contenedor, Finder buscado) =>
      find.descendant(of: contenedor, matching: buscado);

  /// Algún texto de la parada de [rutaId] que contiene [fragmento].
  Finder enLaParada(String rutaId, String fragmento) =>
      dentroDe(parada(rutaId), find.textContaining(fragmento));

  bool vaAntes(WidgetTester tester, String arriba, String abajo) =>
      tester.getTopLeft(parada(arriba)).dy <
      tester.getTopLeft(parada(abajo)).dy;

  group('criterio 1: las rutas oficiales en el orden del administrador', () {
    testWidgets('dibuja una parada por ruta, de la primera a la última', (
      tester,
    ) async {
      // Llegan desordenadas: el orden lo pone la posición.
      await montar(
        tester,
        oficiales: [
          RutaOficial(posicion: 3, ruta: rio),
          RutaOficial(posicion: 1, ruta: estadio),
          RutaOficial(posicion: 2, ruta: nutibara),
        ],
      );

      for (final id in ['ruta-estadio', 'ruta-nutibara', 'ruta-rio']) {
        expect(parada(id), findsOneWidget, reason: id);
      }
      expect(vaAntes(tester, 'ruta-estadio', 'ruta-nutibara'), isTrue);
      expect(vaAntes(tester, 'ruta-nutibara', 'ruta-rio'), isTrue);
    });

    testWidgets('cada parada muestra el nombre, la distancia en km y la '
        'dificultad de su ruta', (tester) async {
      await montar(tester);

      expect(enLaParada('ruta-estadio', 'Vuelta al estadio'), findsOneWidget);
      expect(enLaParada('ruta-estadio', '5.23 km'), findsOneWidget);
      expect(enLaParada('ruta-estadio', 'Fácil'), findsOneWidget);

      expect(enLaParada('ruta-nutibara', 'Cerro Nutibara'), findsOneWidget);
      expect(enLaParada('ruta-nutibara', '7.5 km'), findsOneWidget);
      expect(enLaParada('ruta-nutibara', 'Difícil'), findsOneWidget);

      // 3.0 se escribe "3", como en el resto de la app.
      expect(enLaParada('ruta-rio', '3 km'), findsOneWidget);
      expect(enLaParada('ruta-rio', '3.0'), findsNothing);
    });

    testWidgets('ya no muestra XP: las paradas son rutas, no niveles', (
      tester,
    ) async {
      await montar(tester);

      expect(find.textContaining('XP'), findsNothing);
    });

    testWidgets('una ruta sin dificultad sale "Sin clasificar"', (
      tester,
    ) async {
      await montar(tester);

      expect(
        enLaParada('ruta-rio', TarjetaRutaExplorar.sinDificultad),
        findsOneWidget,
      );
    });

    testWidgets('una ruta sin distancia lo dice en lugar de inventarla', (
      tester,
    ) async {
      await montar(tester, oficiales: enOrden([laureles]));

      expect(
        enLaParada('ruta-laureles', TarjetaRuta.sinDistancia),
        findsOneWidget,
      );
      expect(enLaParada('ruta-laureles', 'km'), findsNothing);
      expect(enLaParada('ruta-laureles', 'Moderada'), findsOneWidget);
    });
  });

  group('criterio 2: el estado de cada parada', () {
    testWidgets('dice "Completada", "Siguiente" o "Bloqueada"', (tester) async {
      await montar(tester, completadas: {'ruta-estadio'});

      expect(
        dentroDe(parada('ruta-estadio'), find.text('Completada')),
        findsOneWidget,
      );
      expect(
        dentroDe(parada('ruta-nutibara'), find.text('Siguiente')),
        findsOneWidget,
      );
      expect(
        dentroDe(parada('ruta-rio'), find.text('Bloqueada')),
        findsOneWidget,
      );
    });

    testWidgets('cada estado lleva su icono, y el de la siguiente no es el '
        'del marcador "Tú": en esa fila irían dos corredores iguales', (
      tester,
    ) async {
      await montar(tester, completadas: {'ruta-estadio'});

      final iconos = {
        'ruta-estadio': Icons.check_circle,
        'ruta-nutibara': Icons.flag_outlined,
        'ruta-rio': Icons.lock_outline,
      };
      for (final MapEntry(key: id, value: icono) in iconos.entries) {
        expect(
          dentroDe(parada(id), find.byIcon(icono)),
          findsOneWidget,
          reason: id,
        );
      }
      // El único corredor de la fila siguiente es el del marcador.
      expect(
        dentroDe(parada('ruta-nutibara'), find.byIcon(Icons.directions_run)),
        findsOneWidget,
      );
    });

    testWidgets('cada parada lleva un solo estado', (tester) async {
      await montar(tester, completadas: {'ruta-estadio'});

      final estadosPorParada = {
        'ruta-estadio': 'Completada',
        'ruta-nutibara': 'Siguiente',
        'ruta-rio': 'Bloqueada',
      };
      for (final MapEntry(key: id, value: propio) in estadosPorParada.entries) {
        for (final otro in ['Completada', 'Siguiente', 'Bloqueada']) {
          expect(
            dentroDe(parada(id), find.text(otro)),
            otro == propio ? findsOneWidget : findsNothing,
            reason: '$id dice "$otro"',
          );
        }
      }
    });

    testWidgets('sin ninguna completada, una siguiente y las demás '
        'bloqueadas', (tester) async {
      await montar(tester);

      expect(
        dentroDe(parada('ruta-estadio'), find.text('Siguiente')),
        findsOneWidget,
      );
      expect(find.text('Siguiente'), findsOneWidget);
      expect(find.text('Bloqueada'), findsNWidgets(2));
      expect(find.text('Completada'), findsNothing);
    });

    testWidgets('completadas todas, ninguna está bloqueada ni es la '
        'siguiente', (tester) async {
      await montar(
        tester,
        completadas: {'ruta-estadio', 'ruta-nutibara', 'ruta-rio'},
      );

      expect(find.text('Completada'), findsNWidgets(3));
      expect(find.text('Siguiente'), findsNothing);
      expect(find.text('Bloqueada'), findsNothing);
    });
  });

  group('criterio 3: el marcador "Tú"', () {
    testWidgets('está en la parada siguiente', (tester) async {
      await montar(tester, completadas: {'ruta-estadio'});

      expect(dentroDe(parada('ruta-nutibara'), marcador), findsOneWidget);
      expect(dentroDe(parada('ruta-estadio'), marcador), findsNothing);
      expect(dentroDe(parada('ruta-rio'), marcador), findsNothing);
      expect(dentroDe(marcador, find.text('Tú')), findsOneWidget);
    });

    testWidgets('sin ninguna completada, está en la primera', (tester) async {
      await montar(tester);

      expect(dentroDe(parada('ruta-estadio'), marcador), findsOneWidget);
    });

    testWidgets('si las completó todas, está en la última', (tester) async {
      await montar(
        tester,
        completadas: {'ruta-estadio', 'ruta-nutibara', 'ruta-rio'},
      );

      expect(dentroDe(parada('ruta-rio'), marcador), findsOneWidget);
      expect(dentroDe(parada('ruta-estadio'), marcador), findsNothing);
    });

    testWidgets('hay uno solo, esté donde esté', (tester) async {
      for (final completadas in <Set<String>>[
        {},
        {'ruta-estadio'},
        {'ruta-rio'},
        {'ruta-estadio', 'ruta-nutibara', 'ruta-rio'},
      ]) {
        await montar(tester, completadas: completadas);

        expect(marcador, findsOneWidget, reason: 'con $completadas');
        expect(find.text('Tú'), findsOneWidget, reason: 'con $completadas');
      }
    });
  });

  group('criterio 4: una ruta completada fuera de orden', () {
    testWidgets('sale completada, pero el marcador sigue en la primera que '
        'falta', (tester) async {
      await montar(tester, completadas: {'ruta-rio'});

      expect(
        dentroDe(parada('ruta-rio'), find.text('Completada')),
        findsOneWidget,
      );
      expect(
        dentroDe(parada('ruta-estadio'), find.text('Siguiente')),
        findsOneWidget,
      );
      expect(
        dentroDe(parada('ruta-nutibara'), find.text('Bloqueada')),
        findsOneWidget,
      );
      expect(dentroDe(parada('ruta-estadio'), marcador), findsOneWidget);
      expect(dentroDe(parada('ruta-rio'), marcador), findsNothing);
    });
  });

  group('criterio 6: tocar una parada', () {
    testWidgets('avisa con la ruta de esa parada', (tester) async {
      final tocadas = <Ruta>[];
      await montar(
        tester,
        completadas: {'ruta-estadio'},
        onTapRuta: tocadas.add,
      );

      await tester.tap(parada('ruta-nutibara'));
      await tester.pump();

      expect(tocadas, [nutibara]);
    });

    testWidgets('también una completada o una bloqueada: el detalle explica '
        'por qué no se puede correr', (tester) async {
      final tocadas = <Ruta>[];
      await montar(
        tester,
        completadas: {'ruta-estadio'},
        onTapRuta: tocadas.add,
      );

      await tester.tap(parada('ruta-estadio'));
      await tester.pump();
      await tester.tap(parada('ruta-rio'));
      await tester.pump();

      expect(tocadas.map((r) => r.id), ['ruta-estadio', 'ruta-rio']);
    });

    testWidgets('sin quién escuche, tocar no falla', (tester) async {
      await montar(tester);

      await tester.tap(parada('ruta-estadio'), warnIfMissed: false);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('criterio 7: sin rutas oficiales', () {
    testWidgets('no dibuja paradas ni marcador, y no falla', (tester) async {
      await montar(tester, oficiales: const [], completadas: {'ruta-vieja'});

      expect(tester.takeException(), isNull);
      expect(marcador, findsNothing);
      expect(parada('ruta-vieja'), findsNothing);
      expect(find.text('Siguiente'), findsNothing);
    });
  });

  group('pantalla estrecha', () {
    final largas = enOrden([
      for (final (i, nombre) in [
        'Vuelta completa al estadio Atanasio Girardot',
        'Subida al cerro Nutibara por el pueblito paisa',
        'Parque lineal del río Medellín de norte a sur',
        'Ciclovía de Laureles y la avenida Nutibara',
        'Circuito universitario de la Universidad de Medellín',
        'Loma de Los Balsos hasta el mirador de Las Palmas',
        'Sendero ecológico del cerro El Volador',
        'Gran travesía del valle de Aburrá entero',
      ].indexed)
        rutaDePrueba(
          id: 'larga-$i',
          nombre: nombre,
          estado: EstadoRuta.publicada,
          distanciaKm: 12.345 + i,
          dificultad: i.isEven ? Dificultad.moderada : null,
        ),
    ]);

    for (final (descripcion, completadas) in [
      ('sin completadas', <String>{}),
      ('a mitad de camino', {'larga-0', 'larga-1', 'larga-5'}),
      ('con todas completadas', {for (var i = 0; i < 8; i++) 'larga-$i'}),
    ]) {
      testWidgets('8 rutas de nombres largos no desbordan en 320x568 '
          '($descripcion)', (tester) async {
        tester.view.physicalSize = const Size(320 * 3, 568 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await montar(tester, oficiales: largas, completadas: completadas);

        expect(tester.takeException(), isNull);
        expect(parada('larga-7'), findsOneWidget);
        expect(marcador, findsOneWidget);
      });
    }
  });
}
