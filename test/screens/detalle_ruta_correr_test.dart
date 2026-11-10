import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_oficial.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_oficiales_service.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_oficiales_repository_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas de "Correr esta ruta" en el detalle (rutas oficiales, etapa 3).
///
/// El detalle mira el mapa de progresión del corredor: si la ruta es oficial
/// y es la siguiente del camino, ofrece correrla; si ya la completó o todavía
/// no le toca, dice por qué no. Las demás rutas, o si el mapa no se pudo
/// leer, se ven como siempre.
void main() {
  /// Como llegan las oficiales: `oficiales()` no trae el trazado, que aquí
  /// no se dibuja.
  Ruta comoOficial(Ruta ruta) =>
      rutaDePrueba(id: ruta.id, nombre: ruta.nombre, estado: ruta.estado);

  /// El camino del mapa: estadio, Nutibara y río, en ese orden.
  RutasOficialesRepositorioFalso mapaCon({
    Set<String> completadas = const {'ruta-estadio'},
  }) => RutasOficialesRepositorioFalso(
    oficiales: [_estadio, _nutibara, _rio].map(comoOficial).toList(),
    completadasPorMi: completadas,
  );

  final botonCorrer = find.byKey(DetalleRutaScreen.claveCorrer);

  /// Que el detalle no diga nada de correr la ruta: ni el botón ni por qué
  /// no está.
  void esperarNadaDeCorrer() {
    expect(botonCorrer, findsNothing);
    expect(find.text(_correr), findsNothing);
    expect(find.text(_yaCompletada), findsNothing);
    expect(find.text(_bloqueada), findsNothing);
  }

  group('según la parada del mapa (rutas oficiales, etapa 3, criterio 1)', () {
    testWidgets('en la ruta oficial que es la siguiente del mapa aparece '
        '"Correr esta ruta"', (tester) async {
      await _abrir(tester, rutaId: 'ruta-nutibara', mapa: mapaCon());

      expect(find.text('Cerro Nutibara'), findsOneWidget);
      expect(botonCorrer, findsOneWidget);
      expect(
        find.descendant(of: botonCorrer, matching: find.text(_correr)),
        findsOneWidget,
      );
      expect(find.text(_yaCompletada), findsNothing);
      expect(find.text(_bloqueada), findsNothing);
    });

    testWidgets('sin ninguna completada, la primera del mapa es la siguiente y '
        'ofrece correrla', (tester) async {
      await _abrir(
        tester,
        rutaId: 'ruta-estadio',
        mapa: mapaCon(completadas: const {}),
      );

      expect(botonCorrer, findsOneWidget);
    });

    testWidgets('en una ruta oficial completada no aparece el botón: dice "Ya '
        'completaste esta ruta"', (tester) async {
      await _abrir(tester, rutaId: 'ruta-estadio', mapa: mapaCon());

      expect(find.text('Vuelta al estadio'), findsOneWidget);
      expect(find.text(_yaCompletada), findsOneWidget);
      expect(botonCorrer, findsNothing);
      expect(find.text(_correr), findsNothing);
      expect(find.text(_bloqueada), findsNothing);
    });

    testWidgets('en una ruta oficial bloqueada no aparece el botón: dice '
        '"Completa antes las rutas anteriores del mapa"', (tester) async {
      await _abrir(tester, rutaId: 'ruta-rio', mapa: mapaCon());

      expect(find.text('Parque del río'), findsOneWidget);
      expect(find.text(_bloqueada), findsOneWidget);
      expect(botonCorrer, findsNothing);
      expect(find.text(_correr), findsNothing);
      expect(find.text(_yaCompletada), findsNothing);
    });

    testWidgets('con el camino terminado, la última ruta dice que ya la '
        'completaste', (tester) async {
      await _abrir(
        tester,
        rutaId: 'ruta-rio',
        mapa: mapaCon(
          completadas: const {'ruta-estadio', 'ruta-nutibara', 'ruta-rio'},
        ),
      );

      expect(find.text(_yaCompletada), findsOneWidget);
      expect(botonCorrer, findsNothing);
    });
  });

  group('cuando no aplica (rutas oficiales, etapa 3, criterio 1)', () {
    testWidgets('en una ruta que no es oficial no aparece nada de esto', (
      tester,
    ) async {
      await _abrir(tester, rutaId: 'ruta-otra', mapa: mapaCon());

      expect(find.text('Loma de los Balsos'), findsOneWidget);
      esperarNadaDeCorrer();
    });

    testWidgets('si no hay rutas oficiales, no aparece nada de esto', (
      tester,
    ) async {
      await _abrir(
        tester,
        rutaId: 'ruta-estadio',
        mapa: RutasOficialesRepositorioFalso(),
      );

      expect(find.text('Vuelta al estadio'), findsOneWidget);
      esperarNadaDeCorrer();
    });

    testWidgets('si el mapa no cargó porque falló la lista de oficiales, no '
        'aparece nada de esto', (tester) async {
      await _abrir(
        tester,
        rutaId: 'ruta-nutibara',
        mapa: mapaCon()..errorAlListar = StateError('sin red'),
      );

      // El detalle se ve igual.
      expect(find.text('Cerro Nutibara'), findsOneWidget);
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
      esperarNadaDeCorrer();
    });

    testWidgets('si el mapa no cargó porque fallaron las completadas, no '
        'aparece nada de esto', (tester) async {
      await _abrir(
        tester,
        rutaId: 'ruta-nutibara',
        mapa: mapaCon()..errorAlLeerCompletadas = StateError('sin red'),
      );

      expect(find.text('Cerro Nutibara'), findsOneWidget);
      esperarNadaDeCorrer();
    });

    testWidgets('mientras el mapa no ha cargado no aparece nada de esto, y al '
        'llegar aparece el botón', (tester) async {
      final mapa = _MapaLento(
        oficiales: [_estadio, _nutibara, _rio].map(comoOficial).toList(),
        completadasPorMi: const {'ruta-estadio'},
      );
      await _abrir(tester, rutaId: 'ruta-nutibara', mapa: mapa, asentar: false);

      expect(find.text('Cerro Nutibara'), findsOneWidget);
      esperarNadaDeCorrer();

      mapa.espera.complete();
      await tester.pumpAndSettle();

      expect(botonCorrer, findsOneWidget);
    });

    testWidgets('sin sustituir el repositorio de rutas oficiales, como en las '
        'pruebas que ya existían, el mapa cae en error y el detalle se ve '
        'igual que antes', (tester) async {
      // Sin sustituirlo, el mapa intenta ir a Supabase, que en las pruebas no
      // está inicializado.
      await _abrir(tester, rutaId: 'ruta-nutibara', mapa: null);

      expect(find.text('Cerro Nutibara'), findsOneWidget);
      expect(find.text('5.23 km'), findsOneWidget);
      esperarNadaDeCorrer();
      expect(tester.takeException(), isNull);
    });

    testWidgets('en la vista previa, mientras llega el trazado, no aparece '
        'nada de esto', (tester) async {
      final rutas = _DetalleLento(rutas: [_estadio, _nutibara, _rio, _otra]);
      await _abrir(
        tester,
        rutaId: 'ruta-nutibara',
        mapa: mapaCon(),
        rutas: rutas,
        // Como llega del listado: sin el trazado.
        vistaPrevia: comoOficial(_nutibara),
        asentar: false,
      );

      expect(
        find.byKey(DetalleRutaScreen.claveCargandoTrazado),
        findsOneWidget,
      );
      expect(find.text('Cerro Nutibara'), findsOneWidget);
      esperarNadaDeCorrer();

      // Con la ruta ya cargada, sí.
      rutas.espera.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(DetalleRutaScreen.claveCargandoTrazado), findsNothing);
      expect(botonCorrer, findsOneWidget);
    });

    testWidgets('en la vista previa de una completada tampoco dice que ya la '
        'completaste', (tester) async {
      final rutas = _DetalleLento(rutas: [_estadio, _nutibara, _rio, _otra]);
      await _abrir(
        tester,
        rutaId: 'ruta-estadio',
        mapa: mapaCon(),
        rutas: rutas,
        vistaPrevia: comoOficial(_estadio),
        asentar: false,
      );

      expect(find.text('Vuelta al estadio'), findsOneWidget);
      esperarNadaDeCorrer();

      rutas.espera.complete();
      await tester.pumpAndSettle();
      // Ya cargada, sí lo dice.
      expect(find.text(_yaCompletada), findsOneWidget);
    });
  });

  group(
    'al tocar "Correr esta ruta" (rutas oficiales, etapa 3, criterio 2)',
    () {
      testWidgets('abre /actividad con la ruta completa, con su trazado', (
        tester,
      ) async {
        final apertura = await _abrir(
          tester,
          rutaId: 'ruta-nutibara',
          mapa: mapaCon(),
        );

        await _tocar(tester, botonCorrer);

        expect(find.text(_pantallaActividad), findsOneWidget);
        final extra = apertura.extraDeActividad;
        expect(extra, isA<Ruta>());
        expect((extra as Ruta).id, 'ruta-nutibara');
        expect(extra.nombre, 'Cerro Nutibara');
        expect(extra.trazado, _trazado);
      });

      testWidgets('la abre encima del detalle: al volver, se está otra vez en '
          'la ruta', (tester) async {
        final apertura = await _abrir(
          tester,
          rutaId: 'ruta-nutibara',
          mapa: mapaCon(),
        );

        await _tocar(tester, botonCorrer);
        expect(apertura.router.canPop(), isTrue);
        apertura.router.pop();
        await tester.pumpAndSettle();

        expect(find.text(_pantallaActividad), findsNothing);
        expect(find.text('Cerro Nutibara'), findsOneWidget);
      });

      testWidgets(
        'abierta desde un listado, lleva la ruta completa que llegó y '
        'no la vista previa sin trazado',
        (tester) async {
          final rutas = _DetalleLento(
            rutas: [_estadio, _nutibara, _rio, _otra],
          );
          final apertura = await _abrir(
            tester,
            rutaId: 'ruta-nutibara',
            mapa: mapaCon(),
            rutas: rutas,
            vistaPrevia: comoOficial(_nutibara),
            asentar: false,
          );
          rutas.espera.complete();
          await tester.pumpAndSettle();

          await _tocar(tester, botonCorrer);

          final extra = apertura.extraDeActividad as Ruta?;
          expect(extra?.id, 'ruta-nutibara');
          expect(extra?.trazado, _trazado);
        },
      );
    },
  );
}

const _trazado = [
  PuntoRuta(latitud: 6.2442, longitud: -75.5812),
  PuntoRuta(latitud: 6.2445, longitud: -75.5808),
  PuntoRuta(latitud: 6.2448, longitud: -75.5809),
];

/// Como la guarda la tabla `rutas` y la devuelve el detalle: con el trazado
/// completo.
Ruta _completa(String id, String nombre) => rutaDePrueba(
  id: id,
  nombre: nombre,
  estado: EstadoRuta.publicada,
  trazado: _trazado,
  fechaPublicacion: DateTime(2026, 10, 17, 9),
);

final _estadio = _completa('ruta-estadio', 'Vuelta al estadio');
final _nutibara = _completa('ruta-nutibara', 'Cerro Nutibara');
final _rio = _completa('ruta-rio', 'Parque del río');
// Publicada, pero el administrador no la eligió para el mapa.
final _otra = _completa('ruta-otra', 'Loma de los Balsos');

const _correr = 'Correr esta ruta';
const _yaCompletada = 'Ya completaste esta ruta';
const _bloqueada = 'Completa antes las rutas anteriores del mapa';
const _pantallaActividad = 'Pantalla actividad';

/// Lo que la prueba necesita mirar después de abrir el detalle.
class _Apertura {
  _Apertura(this.router);

  final GoRouter router;

  /// El `extra` con el que se abrió `/actividad`, o null si no se abrió.
  Object? extraDeActividad;
}

/// La ruta completa no llega hasta que la prueba lo decida (SCRUM-250).
class _DetalleLento extends RutasRepositorioFalso {
  _DetalleLento({super.rutas});

  final espera = Completer<void>();

  @override
  Future<Ruta?> ruta(String id) async {
    await espera.future;
    return super.ruta(id);
  }
}

/// El mapa de progresión no responde hasta que la prueba lo decida.
class _MapaLento extends RutasOficialesRepositorioFalso {
  _MapaLento({super.oficiales, super.completadasPorMi});

  final espera = Completer<void>();

  @override
  Future<List<RutaOficial>> oficiales() async {
    await espera.future;
    return super.oficiales();
  }
}

/// Abre el detalle de [rutaId] con el mapa de progresión de [mapa]. Con
/// [mapa] en null no sustituye el repositorio de rutas oficiales, como las
/// pruebas del detalle anteriores a la etapa 3.
///
/// Al lado va `/actividad`, que anota con qué ruta se abrió.
Future<_Apertura> _abrir(
  WidgetTester tester, {
  required String rutaId,
  required RutasOficialesRepository? mapa,
  RutasRepositorioFalso? rutas,
  Ruta? vistaPrevia,
  bool asentar = true,
}) async {
  // Alto de sobra para que la lista del detalle construya todo su
  // contenido: así un "no aparece" no pasa solo porque quedó fuera de la
  // vista.
  tester.view.physicalSize = const Size(390 * 3, 2000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio =
      rutas ?? RutasRepositorioFalso(rutas: [_estadio, _nutibara, _rio, _otra]);

  late final _Apertura apertura;
  final router = GoRouter(
    initialLocation: DetalleRutaScreen.rutaDe(rutaId),
    routes: [
      GoRoute(
        path: DetalleRutaScreen.ruta,
        builder: (_, estado) => DetalleRutaScreen(
          rutaId: estado.pathParameters['rutaId']!,
          vistaPrevia: vistaPrevia,
        ),
      ),
      GoRoute(
        path: '/actividad',
        builder: (_, estado) {
          apertura.extraDeActividad = estado.extra;
          return const Scaffold(body: Text(_pantallaActividad));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  apertura = _Apertura(router);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rutasRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => DateTime(2026, 10, 17, 12)),
        // El mapa no descarga tiles reales.
        proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        if (mapa != null)
          rutasOficialesRepositoryProvider.overrideWithValue(mapa),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  if (asentar) {
    await tester.pumpAndSettle();
  } else {
    // Con algo en camino puede haber un indicador girando: no se asienta.
    await tester.pump();
    await tester.pump();
  }

  return apertura;
}

/// Toca [objetivo] después de llevarlo a la vista.
Future<void> _tocar(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.pumpAndSettle();
  await tester.tap(objetivo);
  await tester.pumpAndSettle();
}
