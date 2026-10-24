import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/filtros_rutas.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_cercana.dart';
import 'package:traza/models/zona.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/publicar_ruta_screen.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/screens/rutas/seccion_rutas.dart';
import 'package:traza/services/busqueda_rutas_provider.dart';
import 'package:traza/services/filtros_rutas_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/services/zonas_service.dart';
import 'package:traza/widgets/ancho_contenido.dart';
import 'package:traza/widgets/aviso_permiso_ubicacion.dart';
import 'package:traza/widgets/chip_filtro.dart';
import 'package:traza/widgets/mapa_trayecto.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/buscador_de_zonas_falso.dart';
import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Rutas que no responden hasta que la prueba lo decida.
class _RutasLentas extends RutasRepositorioFalso {
  _RutasLentas(this.espera);

  final Completer<List<RutaCercana>> espera;

  @override
  Future<List<RutaCercana>> cercanas({
    required double latitud,
    required double longitud,
    required double radioKm,
  }) => espera.future;
}

/// Rutas cuyo detalle completo no llega hasta que la prueba lo decida
/// (SCRUM-250).
class _DetalleLento extends RutasRepositorioFalso {
  _DetalleLento({super.rutas});

  final espera = Completer<Ruta?>();

  @override
  Future<Ruta?> ruta(String id) => espera.future;
}

/// Búsquedas que no responden mientras la prueba tenga una [pendiente]
/// (SCRUM-254).
class _BusquedaLenta extends RutasRepositorioFalso {
  _BusquedaLenta({super.rutas});

  Completer<List<Ruta>>? pendiente;

  @override
  Future<List<Ruta>> buscar({
    required String termino,
    double? latitud,
    double? longitud,
    Zona? zona,
  }) async {
    final enseguida = await super.buscar(
      termino: termino,
      latitud: latitud,
      longitud: longitud,
      zona: zona,
    );
    return pendiente?.future ?? enseguida;
  }
}

/// Pruebas de Explorar rutas, la sección de Rutas (SCRUM-246).
///
/// Reemplaza a la pantalla provisional de SCRUM-284: ahora lista las rutas
/// de la comunidad, de la más cercana a la más lejana.
void main() {
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;
  late RutasRepositorioFalso repositorio;
  late BuscadorDeZonasFalso zonas;

  final ahora = DateTime(2026, 10, 18, 12);

  // La más reciente es la vuelta; la más cercana, la subida.
  final vuelta = rutaDePrueba(
    id: 'r-1',
    nombre: 'Vuelta al estadio',
    estado: EstadoRuta.publicada,
    fechaPublicacion: DateTime(2026, 10, 18, 9),
  );
  final subida = rutaDePrueba(
    id: 'r-2',
    nombre: 'Subida al Nutibara',
    estado: EstadoRuta.publicada,
    distanciaKm: 12.4,
    fechaPublicacion: DateTime(2026, 10, 15, 9),
  );

  setUp(() {
    permisos = _MockPermisosService();
    fuente = FuenteUbicacionFalsa()
      ..puntoActual = puntoDePrueba(latitud: 6.2442, longitud: -75.5812);
    repositorio = RutasRepositorioFalso(rutas: [vuelta, subida])
      ..rutasCercanas = [
        RutaCercana(ruta: subida, distanciaKm: 1.4),
        RutaCercana(ruta: vuelta, distanciaKm: 6.2),
      ];
    zonas = BuscadorDeZonasFalso(zonas: {'envigado': envigado});
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});
  });

  tearDown(() => fuente.cerrar());

  Future<GoRouter> montar(
    WidgetTester tester, {
    EstadoPermiso ubicacion = EstadoPermiso.concedido,
    Future<EstadoPermiso>? permisoPendiente,
    RutasRepositorioFalso? rutas,
    bool esperar = true,
    Size tamano = const Size(390, 844),
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) => permisoPendiente ?? Future.value(ubicacion));

    final router = GoRouter(
      initialLocation: RutasScreen.ruta,
      routes: [
        // La sección tal como la registra la app, con el detalle y publicar
        // (SCRUM-250).
        seccionRutas,
        // Las demás secciones, de mentira: aquí solo importa poder salir.
        for (final seccion in SeccionPrincipal.values)
          if (seccion != SeccionPrincipal.rutas)
            GoRoute(
              path: seccion.ruta,
              builder: (_, _) => Scaffold(body: Text('En ${seccion.etiqueta}')),
            ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permisosServiceProvider.overrideWithValue(permisos),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _PermisosGuardadosFalso(),
          ),
          fuenteUbicacionProvider.overrideWithValue(fuente),
          rutasRepositoryProvider.overrideWithValue(rutas ?? repositorio),
          relojProvider.overrideWithValue(() => ahora),
          // El mapa del detalle no descarga tiles reales.
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
          // Ni la búsqueda por zona le pregunta a Nominatim (SCRUM-255).
          buscadorDeZonasProvider.overrideWithValue(zonas),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return router;
  }

  double altoDe(WidgetTester tester, String texto) =>
      tester.getTopLeft(find.text(texto)).dy;

  /// Lo que la app le anuncia al lector de pantalla.
  List<String> escucharAnuncios(WidgetTester tester) {
    final anuncios = <String>[];
    final mensajero = tester.binding.defaultBinaryMessenger;
    mensajero.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (mensaje) async {
        if (mensaje case {
          'type': 'announce',
          'data': {'message': final String texto},
        }) {
          anuncios.add(texto);
        }
        return null;
      },
    );
    addTearDown(
      () => mensajero.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        null,
      ),
    );
    return anuncios;
  }

  /// Toca un chip de filtro como el usuario: si la fila no lo deja ver,
  /// primero la desliza (SCRUM-267).
  Future<void> tocarChip(WidgetTester tester, Key clave) async {
    final chip = find.byKey(clave);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  /// Elige una dificultad con su chip (SCRUM-267). Null es "Todas". Tocar la
  /// que ya está elegida la quita.
  Future<void> elegirDificultad(WidgetTester tester, Dificultad? dificultad) =>
      tocarChip(tester, RutasScreen.claveDificultad(dificultad));

  Dificultad? dificultadElegida(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(RutasScreen)),
      ).read(dificultadRutasProvider);

  group('la pantalla', () {
    testWidgets('se llama Explorar rutas', (tester) async {
      await montar(tester);

      expect(find.text(RutasScreen.titulo), findsOneWidget);
      expect(RutasScreen.titulo, 'Explorar rutas');
    });

    testWidgets('lleva la barra con la sección de Rutas marcada', (
      tester,
    ) async {
      await montar(tester);

      final barra = tester.widget<NavegacionPrincipal>(
        find.byType(NavegacionPrincipal),
      );
      expect(barra.seccion, SeccionPrincipal.rutas);
    });

    testWidgets('desde aquí se puede ir a otra sección', (tester) async {
      final router = await montar(tester);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(router.routerDelegate.currentConfiguration.uri.path, '/perfil');
    });
  });

  group('la lista', () {
    testWidgets('con la ubicación, va de la más cercana a la más lejana', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      // La subida queda arriba aunque la vuelta sea más reciente.
      expect(
        altoDe(tester, 'Subida al Nutibara'),
        lessThan(altoDe(tester, 'Vuelta al estadio')),
      );
      expect(repositorio.ultimaConsultaCercana?.latitud, 6.2442);
      expect(repositorio.ultimaConsultaCercana?.longitud, -75.5812);
    });

    testWidgets('cada ruta dice cómo se llama, de quién es y cuánto mide', (
      tester,
    ) async {
      await montar(tester);

      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
      expect(find.text('Vuelta al estadio'), findsOneWidget);
      expect(find.textContaining('Por Ana'), findsNWidgets(2));
      expect(find.text('5.23 km'), findsOneWidget);
      expect(find.text('12.4 km'), findsOneWidget);
    });

    testWidgets('cada ruta va en la tarjeta de lado, con su dificultad y su '
        'desnivel (SCRUM-247)', (tester) async {
      await montar(tester);

      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      )) {
        expect(tarjeta.compacta, isFalse);
      }
      expect(find.text(TarjetaRutaExplorar.sinDificultad), findsNWidgets(2));
      expect(find.text(TarjetaRutaExplorar.sinDesnivel), findsNWidgets(2));
    });

    testWidgets('sin permiso de ubicación, las más recientes y lo dice', (
      tester,
    ) async {
      await montar(tester, ubicacion: EstadoPermiso.denegado);

      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);
      expect(find.text(RutasScreen.rotuloCercania), findsNothing);
      // Ahora la vuelta, que es la más reciente, va primero.
      expect(
        altoDe(tester, 'Vuelta al estadio'),
        lessThan(altoDe(tester, 'Subida al Nutibara')),
      );
      expect(repositorio.consultasCercanas, 0);
    });

    testWidgets('con la ubicación del teléfono apagada, también las '
        'recientes', (tester) async {
      fuente.servicio = false;

      await montar(tester);

      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
    });

    testWidgets('sin rutas, lo dice en vez de dejar la lista en blanco', (
      tester,
    ) async {
      repositorio.rutasCercanas = const [];

      await montar(tester);

      expect(find.text(RutasScreen.sinRutasCerca), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
    });
  });

  group('estados vacío y de error (SCRUM-249)', () {
    testWidgets('sin rutas cerca, dice que no las encontró y a qué '
        'distancia buscó', (tester) async {
      // Hay rutas en la comunidad, pero ninguna a menos de 50 km.
      repositorio.rutasCercanas = const [];

      await montar(tester);

      expect(find.byKey(RutasScreen.claveSinRutasCerca), findsOneWidget);
      expect(find.text(RutasScreen.sinRutasCerca), findsOneWidget);
      expect(find.textContaining('a menos de 50 km'), findsOneWidget);
      // Ni el rótulo ni una lista vacía: el mensaje en su lugar.
      expect(find.byKey(RutasScreen.claveOrden), findsNothing);
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
    });

    testWidgets('sin ninguna ruta publicada, dice eso otro y cómo publicar '
        'una', (tester) async {
      repositorio = RutasRepositorioFalso(rutas: const []);

      // Sin permiso, se ven las recientes de toda la comunidad: no hay.
      await montar(tester, ubicacion: EstadoPermiso.denegado);

      expect(find.byKey(RutasScreen.claveSinRutas), findsOneWidget);
      expect(find.text(RutasScreen.sinRutas), findsOneWidget);
      expect(find.textContaining('desde el resumen'), findsOneWidget);
      expect(find.text(RutasScreen.sinRutasCerca), findsNothing);
    });

    testWidgets('sin rutas cerca, deslizar hacia abajo vuelve a buscar', (
      tester,
    ) async {
      repositorio.rutasCercanas = const [];
      await montar(tester);

      // Ya hay una publicada por aquí.
      repositorio.rutasCercanas = [RutaCercana(ruta: vuelta, distanciaKm: 2)];
      await tester.fling(
        find.byKey(RutasScreen.claveSinRutasCerca),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Vuelta al estadio'), findsOneWidget);
      expect(repositorio.consultasCercanas, 2);
    });

    testWidgets('sin conexión, pide revisarla', (tester) async {
      // Lo que lanza el cliente HTTP cuando la petición no llega.
      repositorio.error = http.ClientException('Failed host lookup');

      await montar(tester);

      expect(find.byKey(RutasScreen.claveError), findsOneWidget);
      expect(find.text(RutasScreen.errorTitulo), findsOneWidget);
      expect(find.text(RutasScreen.errorDeConexion), findsOneWidget);
      expect(find.byKey(RutasScreen.claveReintentar), findsOneWidget);
    });

    testWidgets('si la base responde con un error, no culpa a la conexión', (
      tester,
    ) async {
      repositorio.error = const PostgrestException(
        message: 'Error de prueba',
        code: '500',
      );

      await montar(tester);

      expect(find.text(RutasScreen.errorDeLaBase), findsOneWidget);
      expect(find.text(RutasScreen.errorDeConexion), findsNothing);
    });

    testWidgets('si los datos no se entienden, tampoco', (tester) async {
      repositorio.error = const FormatException('fila rara');

      await montar(tester);

      expect(find.text(RutasScreen.errorDeLaBase), findsOneWidget);
    });

    testWidgets('tras un error de la base, "Reintentar" recupera la lista', (
      tester,
    ) async {
      repositorio.error = const PostgrestException(message: 'Error de prueba');
      await montar(tester);

      repositorio.error = null;
      await tester.tap(find.byKey(RutasScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.byKey(RutasScreen.claveError), findsNothing);
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
    });

    group('sin saber dónde está, aunque el permiso esté', () {
      testWidgets('con la ubicación apagada, lo dice arriba de las '
          'recientes', (tester) async {
        fuente.servicio = false;

        await montar(tester);

        expect(find.byKey(RutasScreen.claveAvisoUbicacion), findsOneWidget);
        expect(find.text(RutasScreen.ubicacionApagada), findsOneWidget);
        expect(find.textContaining('Enciéndela'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(RutasScreen.claveAvisoUbicacion)).dy,
          lessThan(
            tester.getTopLeft(find.text(RutasScreen.rotuloRecientes)).dy,
          ),
        );
      });

      testWidgets('si el GPS no responde, lo dice y sugiere qué hacer', (
        tester,
      ) async {
        fuente.errorAlLeer = Exception('sin fix');

        await montar(tester);

        expect(find.text(RutasScreen.ubicacionSinRespuesta), findsOneWidget);
        expect(find.textContaining('acércate a una ventana'), findsOneWidget);
        expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
      });

      testWidgets('al encenderla y reintentar, la lista vuelve por cercanía', (
        tester,
      ) async {
        fuente.servicio = false;
        await montar(tester);

        fuente.servicio = true;
        await tester.tap(find.byKey(RutasScreen.claveReintentarUbicacion));
        await tester.pumpAndSettle();

        expect(find.byKey(RutasScreen.claveAvisoUbicacion), findsNothing);
        expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
        expect(find.text(RutasScreen.todaviaSinUbicacion), findsNothing);
      });

      testWidgets('si al reintentar sigue sin ubicarse, lo dice', (
        tester,
      ) async {
        fuente.errorAlLeer = Exception('sin fix');
        await montar(tester);

        await tester.tap(find.byKey(RutasScreen.claveReintentarUbicacion));
        await tester.pumpAndSettle();

        // El toque no se pierde sin respuesta.
        expect(find.text(RutasScreen.todaviaSinUbicacion), findsOneWidget);
        expect(find.byKey(RutasScreen.claveAvisoUbicacion), findsOneWidget);
      });

      testWidgets('el aviso del permiso no sale: el permiso sí está', (
        tester,
      ) async {
        fuente.servicio = false;

        await montar(tester);

        expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
      });
    });

    testWidgets('en la pantalla más estrecha y con texto grande, ningún '
        'estado desborda', (tester) async {
      for (final preparar in <void Function()>[
        // Sin rutas cerca.
        () => repositorio.rutasCercanas = const [],
        // Sin conexión.
        () => repositorio.error = http.ClientException('sin red'),
        // GPS sin respuesta, con su aviso arriba.
        () => fuente.errorAlLeer = Exception('sin fix'),
      ]) {
        repositorio = RutasRepositorioFalso(rutas: [vuelta, subida]);
        fuente
          ..servicio = true
          ..errorAlLeer = null;
        preparar();

        await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

        expect(tester.takeException(), isNull);
      }
    });
  });

  group('el permiso de ubicación (SCRUM-248)', () {
    /// El usuario sale a los ajustes del teléfono y vuelve a la app, pasando
    /// por cada estado intermedio como lo hace el sistema.
    Future<void> irYVolverDeLosAjustes(WidgetTester tester) async {
      for (final estado in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(estado);
      }
      await tester.pumpAndSettle();
    }

    testWidgets('sin él, explica para qué hace falta arriba de la lista', (
      tester,
    ) async {
      await montar(tester, ubicacion: EstadoPermiso.denegado);

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsOneWidget);
      expect(find.text(AvisoPermisoUbicacion.porQue), findsOneWidget);
      // Las rutas siguen ahí, por fecha: se puede explorar igual.
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.byKey(AvisoPermisoUbicacion.clave)).dy,
        lessThan(tester.getTopLeft(find.text(RutasScreen.rotuloRecientes)).dy),
      );
    });

    testWidgets('con él, no hay nada que pedir', (tester) async {
      await montar(tester);

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
    });

    testWidgets('con la ubicación del teléfono apagada el permiso sí está: '
        'este aviso no es el que toca', (tester) async {
      fuente.servicio = false;

      await montar(tester);

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);
    });

    testWidgets('al concederlo, la lista vuelve por cercanía sola', (
      tester,
    ) async {
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await montar(tester, ubicacion: EstadoPermiso.denegado);
      expect(repositorio.consultasCercanas, 0);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(find.text(RutasScreen.rotuloRecientes), findsNothing);
      // Ahora la subida, que es la más cercana, va primero.
      expect(
        altoDe(tester, 'Subida al Nutibara'),
        lessThan(altoDe(tester, 'Vuelta al estadio')),
      );
      expect(repositorio.consultasCercanas, 1);
      expect(fuente.lecturasPuntuales, 1);
    });

    testWidgets('si lo vuelve a negar, sigue el aviso con las recientes', (
      tester,
    ) async {
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.denegado);
      await montar(tester, ubicacion: EstadoPermiso.denegado);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsOneWidget);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);
      expect(repositorio.consultasCercanas, 0);
      // Sin permiso no se le pregunta nada al GPS.
      expect(fuente.lecturasPuntuales, 0);
    });

    testWidgets('bloqueado, manda a los ajustes y al volver con el permiso '
        'la lista se recupera sola', (tester) async {
      await montar(tester, ubicacion: EstadoPermiso.bloqueado);

      await tester.tap(find.text('Abrir ajustes'));
      await tester.pumpAndSettle();
      verify(() => permisos.abrirAjustes()).called(1);

      // Allá lo concedió.
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await irYVolverDeLosAjustes(tester);

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(repositorio.consultasCercanas, 1);
    });

    testWidgets('si vuelve de los ajustes sin concederlo, todo sigue igual', (
      tester,
    ) async {
      await montar(tester, ubicacion: EstadoPermiso.bloqueado);

      await irYVolverDeLosAjustes(tester);

      expect(find.byKey(AvisoPermisoUbicacion.clave), findsOneWidget);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);
    });
  });

  group('carga y error', () {
    testWidgets('mientras consulta, se ve que está cargando', (tester) async {
      final espera = Completer<List<RutaCercana>>();

      await montar(tester, rutas: _RutasLentas(espera), esperar: false);
      // Un par de vueltas para que la ubicación responda y salga la consulta.
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNothing);

      espera.complete([RutaCercana(ruta: vuelta, distanciaKm: 2)]);
      await tester.pumpAndSettle();

      expect(find.text('Vuelta al estadio'), findsOneWidget);
    });

    testWidgets('mientras no se sepa el permiso, no muestra una lista que '
        'después salte', (tester) async {
      final permiso = Completer<EstadoPermiso>();

      await montar(tester, permisoPendiente: permiso.future, esperar: false);
      await tester.pump();

      // Ni las recientes ni las cercanas: todavía no se sabe cuál toca.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repositorio.consultasPublicadas, 0);
      expect(repositorio.consultasCercanas, 0);

      permiso.complete(EstadoPermiso.concedido);
      await tester.pumpAndSettle();

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(repositorio.consultasPublicadas, 0);
    });

    testWidgets('si falla, lo dice y "Reintentar" vuelve a consultar', (
      tester,
    ) async {
      repositorio.error = Exception('sin red');
      await montar(tester);

      expect(find.text('No pudimos cargar las rutas'), findsOneWidget);

      repositorio.error = null;
      await tester.tap(find.byKey(RutasScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar las rutas'), findsNothing);
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
      expect(repositorio.consultasCercanas, 2);
    });

    testWidgets('deslizar hacia abajo vuelve a leer la ubicación y las rutas', (
      tester,
    ) async {
      await montar(tester);
      expect(fuente.lecturasPuntuales, 1);
      expect(repositorio.consultasCercanas, 1);

      await tester.fling(
        find.byKey(RutasScreen.claveLista),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      // El usuario pudo moverse: se le pregunta otra vez dónde está.
      expect(fuente.lecturasPuntuales, 2);
      expect(repositorio.consultasCercanas, 2);
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
    });
  });

  group('en cualquier pantalla', () {
    testWidgets('en la más estrecha no desborda', (tester) async {
      await montar(tester, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
      expect(find.text(RutasScreen.titulo), findsOneWidget);
      expect(find.text('Subida al Nutibara'), findsOneWidget);
    });

    testWidgets('con el texto del sistema grande tampoco', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
    });

    testWidgets('el aviso de permiso tampoco, ni bloqueado, que es el texto '
        'más largo', (tester) async {
      await montar(
        tester,
        ubicacion: EstadoPermiso.bloqueado,
        tamano: const Size(320, 568),
        escalaTexto: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Abrir ajustes'), findsOneWidget);
    });

    testWidgets('en una tableta las tarjetas no se estiran de borde a borde', (
      tester,
    ) async {
      await montar(tester, tamano: const Size(768, 1024));

      // El mismo ancho máximo que el resto de la app en pantallas grandes.
      final tarjeta = tester.getRect(find.byType(TarjetaRutaExplorar).first);
      expect(tarjeta.width, lessThanOrEqualTo(AnchoContenido.maximo));
    });
  });

  group('abrir el detalle (SCRUM-250, criterio 5 de HU-29)', () {
    DetalleRutaScreen detalle(WidgetTester tester) =>
        tester.widget<DetalleRutaScreen>(find.byType(DetalleRutaScreen));

    testWidgets('al tocar una ruta cercana se abre el detalle de esa ruta', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('r-2')));
      await tester.pumpAndSettle();

      expect(detalle(tester).rutaId, 'r-2');
      expect(find.text('Subida al Nutibara'), findsOneWidget);
      expect(find.text('12.4 km'), findsOneWidget);
      // La otra se quedó en la lista, debajo.
      expect(find.text('Vuelta al estadio'), findsNothing);
    });

    testWidgets('también desde las más recientes, sin ubicación', (
      tester,
    ) async {
      await montar(tester, ubicacion: EstadoPermiso.denegado);

      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('r-1')));
      await tester.pumpAndSettle();

      expect(detalle(tester).rutaId, 'r-1');
      expect(find.text('Vuelta al estadio'), findsOneWidget);
    });

    testWidgets('la ruta elegida viaja al detalle, que la muestra mientras '
        'llega su trazado', (tester) async {
      final lento = _DetalleLento(rutas: [vuelta, subida])
        ..rutasCercanas = repositorio.rutasCercanas;
      await montar(tester, rutas: lento);

      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('r-2')));
      await tester.pump();
      // La transición. Con el indicador del mapa girando no se asienta.
      await tester.pump(const Duration(seconds: 1));

      expect(detalle(tester).vistaPrevia, same(subida));
      // Sin el trazado todavía, ya dice qué ruta es y cuánto mide.
      expect(find.text('Subida al Nutibara'), findsOneWidget);
      expect(find.text('12.4 km'), findsOneWidget);
      expect(
        find.byKey(DetalleRutaScreen.claveCargandoTrazado),
        findsOneWidget,
      );

      lento.espera.complete(
        rutaDePrueba(
          id: 'r-2',
          nombre: 'Subida al Nutibara',
          estado: EstadoRuta.publicada,
          distanciaKm: 12.4,
          fechaPublicacion: DateTime(2026, 10, 15, 9),
          trazado: const [
            PuntoRuta(latitud: 6.2442, longitud: -75.5812),
            PuntoRuta(latitud: 6.2450, longitud: -75.5800),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(DetalleRutaScreen.claveCargandoTrazado), findsNothing);
      expect(find.byType(MapaTrayecto), findsOneWidget);
    });

    testWidgets('"atrás" vuelve a la lista donde estaba, sin consultarla otra '
        'vez', (tester) async {
      final muchas = [
        for (var i = 0; i < 12; i++)
          rutaDePrueba(
            id: 'r-$i',
            nombre: 'Ruta $i',
            estado: EstadoRuta.publicada,
          ),
      ];
      repositorio = RutasRepositorioFalso(rutas: muchas)
        ..rutasCercanas = [
          for (final (i, ruta) in muchas.indexed)
            RutaCercana(ruta: ruta, distanciaKm: i + 1.0),
        ];
      await montar(tester);

      final lista = find
          .descendant(
            of: find.byKey(RutasScreen.claveLista),
            matching: find.byType(Scrollable),
          )
          .first;
      final septima = find.byKey(TarjetaRutaExplorar.claveDe('r-7'));
      await tester.scrollUntilVisible(septima, 300, scrollable: lista);
      await tester.pumpAndSettle();
      final antes = tester.state<ScrollableState>(lista).position.pixels;
      expect(antes, greaterThan(0));

      await tester.tap(septima);
      await tester.pumpAndSettle();
      expect(detalle(tester).rutaId, 'r-7');

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.byType(DetalleRutaScreen), findsNothing);
      expect(tester.state<ScrollableState>(lista).position.pixels, antes);
      expect(septima, findsOneWidget);
      expect(repositorio.consultasCercanas, 1);
    });

    testWidgets('el "atrás" del sistema también vuelve a la lista', (
      tester,
    ) async {
      await montar(tester);

      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('r-2')));
      await tester.pumpAndSettle();
      expect(find.byType(DetalleRutaScreen), findsOneWidget);

      // El botón atrás de Android.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(DetalleRutaScreen), findsNothing);
      expect(find.byKey(RutasScreen.claveLista), findsOneWidget);
    });
  });

  group('la ruta de navegación (SCRUM-250)', () {
    testWidgets('el detalle cuelga de Explorar rutas: si se llega por un '
        'enlace, al cerrarlo queda la lista', (tester) async {
      final router = await montar(tester);
      router.go(SeccionPrincipal.foro.ruta);
      await tester.pumpAndSettle();

      router.go(DetalleRutaScreen.rutaDe('r-1'));
      await tester.pumpAndSettle();

      final abierto = tester.widget<DetalleRutaScreen>(
        find.byType(DetalleRutaScreen),
      );
      expect(abierto.rutaId, 'r-1');
      // Sin la ruta del listado, el detalle la pide por su id.
      expect(abierto.vistaPrevia, isNull);
      expect(find.text('Vuelta al estadio'), findsOneWidget);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.byType(DetalleRutaScreen), findsNothing);
      expect(find.byType(RutasScreen), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        RutasScreen.ruta,
      );
    });

    testWidgets('abierto con `push` desde otra pantalla, como lo abre el '
        'foro, se apila solo y al cerrarlo vuelve a ella', (tester) async {
      final router = await montar(tester);
      router.go(SeccionPrincipal.foro.ruta);
      await tester.pumpAndSettle();

      router.push(DetalleRutaScreen.rutaDe('r-1'));
      await tester.pumpAndSettle();

      expect(find.byType(DetalleRutaScreen), findsOneWidget);
      // Debajo no se armó la lista: solo el detalle encima del foro.
      expect(find.byType(RutasScreen, skipOffstage: false), findsNothing);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.text('En ${SeccionPrincipal.foro.etiqueta}'), findsOneWidget);
    });

    testWidgets('publicar una ruta no se toma por el id de una', (
      tester,
    ) async {
      // Antes, con el detalle registrado primero, '/rutas/publicar' abría el
      // detalle de una ruta llamada "publicar".
      final router = await montar(tester);

      router.push(PublicarRutaScreen.ruta);
      await tester.pumpAndSettle();

      expect(find.byType(PublicarRutaScreen), findsOneWidget);
      expect(find.byType(DetalleRutaScreen), findsNothing);
    });
  });

  group('la barra de búsqueda (SCRUM-254)', () {
    /// Escribe en la barra y deja pasar la espera y la consulta.
    Future<void> buscar(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
    }

    /// Los nombres de las rutas a la vista, de arriba abajo.
    List<String> enPantalla(WidgetTester tester) => [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.nombre,
    ];

    testWidgets('va encima de la lista y dice qué se puede buscar', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text(RutasScreen.pistaBusqueda), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byKey(RutasScreen.claveBusqueda)).dy,
        lessThanOrEqualTo(altoDe(tester, RutasScreen.rotuloCercania)),
      );
      // Nombres de lugares y de personas: sin corrector que los cambie.
      expect(
        tester
            .widget<TextField>(find.byKey(RutasScreen.claveBusqueda))
            .autocorrect,
        isFalse,
      );
    });

    testWidgets('al escribir, la lista muestra lo que coincide, con las '
        'mismas tarjetas', (tester) async {
      await montar(tester);

      await buscar(tester, 'nutibara');

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(find.text(RutasScreen.rotuloCercania), findsNothing);
      expect(enPantalla(tester), ['Subida al Nutibara']);
      // La tarjeta de lado de la lista de siempre, con sus datos.
      expect(
        tester
            .widget<TarjetaRutaExplorar>(find.byType(TarjetaRutaExplorar))
            .compacta,
        isFalse,
      );
      expect(find.text('12.4 km'), findsOneWidget);
      expect(find.byKey(RutasScreen.claveResultados), findsOneWidget);
    });

    testWidgets('también encuentra por quien creó la ruta', (tester) async {
      repositorio = RutasRepositorioFalso(
        rutas: [
          vuelta,
          subida,
          rutaDePrueba(
            id: 'r-3',
            nombre: 'Loma de Envigado',
            autorNombre: 'Luis',
            estado: EstadoRuta.publicada,
            fechaPublicacion: DateTime(2026, 10, 16, 9),
          ),
        ],
      );
      await montar(tester);

      await buscar(tester, 'luis');

      expect(enPantalla(tester), ['Loma de Envigado']);
      expect(find.text('Por Luis'), findsOneWidget);
    });

    testWidgets('con una sola letra siguen las cercanas y no consulta', (
      tester,
    ) async {
      await montar(tester);

      await buscar(tester, 'n');

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
      expect(repositorio.busquedas, isEmpty);
    });

    testWidgets('espera a que termine de escribir: sale una sola consulta', (
      tester,
    ) async {
      await montar(tester);

      for (final texto in ['nu', 'nuti', 'nutibara']) {
        await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
        // Un cuadro, como en el teléfono, y la siguiente letra a los 100 ms.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();

      expect([for (final b in repositorio.busquedas) b.termino], ['nutibara']);
    });

    testWidgets('con la ubicación, pide los resultados ordenados desde donde '
        'está el usuario', (tester) async {
      await montar(tester);

      await buscar(tester, 'nutibara');

      expect(repositorio.busquedas.single.latitud, 6.2442);
      expect(repositorio.busquedas.single.longitud, -75.5812);
    });

    testWidgets('sin el permiso busca igual, y su aviso no se mete entre los '
        'resultados', (tester) async {
      await montar(tester, ubicacion: EstadoPermiso.denegado);
      expect(find.byKey(AvisoPermisoUbicacion.clave), findsOneWidget);

      await buscar(tester, 'nutibara');

      expect(repositorio.busquedas.single.latitud, isNull);
      expect(enPantalla(tester), ['Subida al Nutibara']);
      expect(find.byKey(AvisoPermisoUbicacion.clave), findsNothing);
    });

    testWidgets('al borrar lo escrito vuelven las cercanas al instante, sin '
        'consultarlas otra vez', (tester) async {
      await montar(tester);
      await buscar(tester, 'nutibara');

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), '');
      await tester.pump();

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(enPantalla(tester), ['Subida al Nutibara', 'Vuelta al estadio']);
      expect(repositorio.consultasCercanas, 1);
    });

    testWidgets('tocar un resultado abre su detalle, y al volver la búsqueda '
        'sigue ahí', (tester) async {
      await montar(tester);
      await buscar(tester, 'nutibara');

      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('r-2')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DetalleRutaScreen>(find.byType(DetalleRutaScreen)).rutaId,
        'r-2',
      );

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(find.text('nutibara'), findsOneWidget);
      expect(repositorio.busquedas, hasLength(1));
    });

    testWidgets('si la búsqueda falla lo dice, y "Reintentar" la repite', (
      tester,
    ) async {
      repositorio.errorBusqueda = StateError('sin red');
      await montar(tester);

      await buscar(tester, 'nutibara');

      expect(find.byKey(RutasScreen.claveError), findsOneWidget);
      expect(find.text(RutasScreen.errorDeConexion), findsOneWidget);

      repositorio.errorBusqueda = null;
      await tester.tap(find.byKey(RutasScreen.claveReintentar));
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();

      expect(enPantalla(tester), ['Subida al Nutibara']);
    });

    testWidgets('mientras llega lo de la última letra se quedan los '
        'resultados de antes', (tester) async {
      final lenta = _BusquedaLenta(rutas: [vuelta, subida])
        ..rutasCercanas = repositorio.rutasCercanas;
      await montar(tester, rutas: lenta);
      await buscar(tester, 'nutibara');

      final pendiente = lenta.pendiente = Completer();
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), 'nutibar');
      await tester.pump(esperaBusquedaRutas);
      await tester.pump();

      // Los de antes siguen, con el indicador junto al rótulo.
      expect(enPantalla(tester), ['Subida al Nutibara']);
      expect(find.byKey(RutasScreen.claveBuscando), findsOneWidget);

      pendiente.complete([subida]);
      await tester.pumpAndSettle();

      expect(find.byKey(RutasScreen.claveBuscando), findsNothing);
      expect(enPantalla(tester), ['Subida al Nutibara']);
    });

    testWidgets('sin coincidencias lo dice, en vez de dejar la lista en '
        'blanco', (tester) async {
      await montar(tester);

      await buscar(tester, 'zzz');

      expect(find.byKey(RutasScreen.claveSinResultados), findsOneWidget);
      expect(find.text(RutasScreen.sinResultados), findsOneWidget);
      expect(find.textContaining('«zzz»'), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
    });

    testWidgets('deslizar hacia abajo repite la búsqueda', (tester) async {
      await montar(tester);
      await buscar(tester, 'nutibara');

      await tester.fling(
        find.byKey(RutasScreen.claveResultados),
        const Offset(0, 400),
        1000,
      );
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();

      expect(repositorio.busquedas, hasLength(2));
      expect(enPantalla(tester), ['Subida al Nutibara']);
    });

    testWidgets('al deslizar los resultados se esconde el teclado', (
      tester,
    ) async {
      await montar(tester);
      await buscar(tester, 'nutibara');

      expect(
        tester
            .widget<ListView>(find.byKey(RutasScreen.claveResultados))
            .keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
    });

    testWidgets('en la pantalla más estrecha con el texto grande, ni la '
        'barra ni los resultados desbordan', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

      await buscar(tester, 'nutibara');

      expect(tester.takeException(), isNull);
      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
    });
  });

  group('buscar por zona (SCRUM-255, criterio 2 de HU-30)', () {
    // Arranca en Envigado y no lo dice en su nombre: solo la encuentra la
    // búsqueda por zona.
    final escobero = rutaDePrueba(
      id: 'r-3',
      nombre: 'Loma del Escobero',
      autorNombre: 'Luis',
      estado: EstadoRuta.publicada,
      fechaPublicacion: DateTime(2026, 10, 16, 9),
    );

    Future<void> escribir(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
    }

    /// La tecla de buscar del teclado, o Enter en el navegador.
    Future<void> confirmar(WidgetTester tester) async {
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    }

    List<String> enPantalla(WidgetTester tester) => [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.nombre,
    ];

    testWidgets('mientras escribe no pregunta por ningún lugar', (
      tester,
    ) async {
      repositorio.rutasEnZona = [escobero];
      await montar(tester);

      await escribir(tester, 'envigado');

      expect(zonas.consultas, isEmpty);
      expect(repositorio.busquedas.single.zona, isNull);
      expect(find.byKey(RutasScreen.claveNotaZona), findsNothing);
    });

    testWidgets('al confirmar suma las rutas que arrancan en ese lugar, '
        'aunque estén lejos, en la misma lista y con la misma tarjeta', (
      tester,
    ) async {
      final vueltaEnvigado = rutaDePrueba(
        id: 'r-4',
        nombre: 'Vuelta a Envigado',
        estado: EstadoRuta.publicada,
        fechaPublicacion: DateTime(2026, 10, 17, 9),
      );
      repositorio = RutasRepositorioFalso(
        rutas: [vuelta, subida, vueltaEnvigado],
      )..rutasEnZona = [escobero];
      await montar(tester);

      await escribir(tester, 'envigado');
      await confirmar(tester);

      expect([for (final c in zonas.consultas) c.texto], ['envigado']);
      expect(repositorio.busquedas.last.zona, envigado);
      // La que se llama así y la que arranca allá.
      expect(enPantalla(tester), ['Vuelta a Envigado', 'Loma del Escobero']);
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      )) {
        expect(tarjeta.compacta, isFalse);
      }
    });

    testWidgets('dice qué lugar encontró, con su departamento, y de dónde '
        'salió', (tester) async {
      repositorio.rutasEnZona = [escobero];
      await montar(tester);

      await escribir(tester, 'envigado');
      await confirmar(tester);

      final nota = find.byKey(RutasScreen.claveNotaZona);
      expect(
        find.descendant(
          of: nota,
          matching: find.textContaining(
            'Envigado, Antioquia',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: nota,
          matching: find.text(RutasScreen.atribucionZonas),
        ),
        findsOneWidget,
      );
    });

    testWidgets('con la ubicación del usuario, la pasa para preferir los '
        'lugares cercanos', (tester) async {
      await montar(tester);

      await escribir(tester, 'envigado');
      await confirmar(tester);

      expect(zonas.consultas.single.latitud, 6.2442);
      expect(zonas.consultas.single.longitud, -75.5812);
    });

    testWidgets('si vuelve a escribir, deja de buscar en el lugar', (
      tester,
    ) async {
      repositorio.rutasEnZona = [escobero];
      await montar(tester);
      await escribir(tester, 'envigado');
      await confirmar(tester);
      expect(find.byKey(RutasScreen.claveNotaZona), findsOneWidget);

      await escribir(tester, 'envigad');

      expect(find.byKey(RutasScreen.claveNotaZona), findsNothing);
      expect(repositorio.busquedas.last.zona, isNull);
      expect(find.text('Loma del Escobero'), findsNothing);
    });

    testWidgets('sin coincidencias por nombre, ofrece buscar lo escrito como '
        'lugar', (tester) async {
      repositorio.rutasEnZona = [escobero];
      await montar(tester);

      await escribir(tester, 'envigado');
      expect(find.byKey(RutasScreen.claveSinResultados), findsOneWidget);

      await tester.tap(find.byKey(RutasScreen.claveBuscarComoLugar));
      await tester.pumpAndSettle();

      expect(enPantalla(tester), ['Loma del Escobero']);
      expect(find.byKey(RutasScreen.claveNotaZona), findsOneWidget);
    });

    testWidgets('si lo escrito no es un lugar, lo dice', (tester) async {
      await montar(tester);

      await escribir(tester, 'zzz');
      await confirmar(tester);

      expect([for (final c in zonas.consultas) c.texto], ['zzz']);
      expect(
        find.textContaining('no encontramos un lugar con ese nombre'),
        findsOneWidget,
      );
      expect(find.byKey(RutasScreen.claveBuscarComoLugar), findsNothing);
    });

    testWidgets('si no se pudo preguntar por el lugar, muestra lo que '
        'coincide por nombre y lo dice', (tester) async {
      zonas.error = const ZonaNoDisponibleException('sin conexión');
      await montar(tester);

      await escribir(tester, 'nutibara');
      await confirmar(tester);

      expect(enPantalla(tester), ['Subida al Nutibara']);
      expect(find.byKey(RutasScreen.claveSinZona), findsOneWidget);
    });

    testWidgets('sin nada por nombre y sin poder preguntar por el lugar, '
        'deja reintentar', (tester) async {
      zonas.error = const ZonaNoDisponibleException('sin conexión');
      repositorio.rutasEnZona = [escobero];
      await montar(tester);

      await escribir(tester, 'envigado');
      await confirmar(tester);
      expect(find.textContaining('Revisa tu conexión'), findsOneWidget);

      zonas.error = null;
      await tester.tap(find.byKey(RutasScreen.claveReintentarZona));
      await tester.pumpAndSettle();

      expect(enPantalla(tester), ['Loma del Escobero']);
      expect(find.byKey(RutasScreen.claveNotaZona), findsOneWidget);
    });

    testWidgets('en la pantalla más estrecha con el texto grande, la nota '
        'del lugar no desborda', (tester) async {
      repositorio.rutasEnZona = [escobero];
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

      await escribir(tester, 'envigado');
      await confirmar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(RutasScreen.claveNotaZona), findsOneWidget);
    });
  });

  group('buscar por creador (SCRUM-256, criterio 3 de HU-30)', () {
    final deMariana = rutaDePrueba(
      id: 'r-5',
      nombre: 'Vuelta a la represa',
      autorNombre: 'Mariana Ríos',
      estado: EstadoRuta.publicada,
      fechaPublicacion: DateTime(2026, 10, 14, 9),
    );
    final deLuis = rutaDePrueba(
      id: 'r-6',
      nombre: 'Cerro de las tres cruces',
      autorNombre: 'Luis Pérez',
      estado: EstadoRuta.publicada,
      fechaPublicacion: DateTime(2026, 10, 13, 9),
    );

    // Las dos del setUp son de Ana.
    setUp(
      () => repositorio = RutasRepositorioFalso(
        rutas: [vuelta, subida, deMariana, deLuis],
      ),
    );

    Future<void> escribir(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
    }

    List<String> enPantalla(WidgetTester tester) => [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.nombre,
    ];

    testWidgets('con el nombre de quien la publicó salen sus rutas', (
      tester,
    ) async {
      await montar(tester);

      await escribir(tester, 'luis');

      expect(enPantalla(tester), ['Cerro de las tres cruces']);
      expect(find.text('Por Luis Pérez'), findsOneWidget);
    });

    testWidgets('también con el apellido, sin tilde', (tester) async {
      await montar(tester);

      await escribir(tester, 'perez');

      expect(enPantalla(tester), ['Cerro de las tres cruces']);
    });

    testWidgets('no confunde personas: "ana" no trae las rutas de Mariana', (
      tester,
    ) async {
      await montar(tester);

      await escribir(tester, 'ana');

      expect(enPantalla(tester), ['Vuelta al estadio', 'Subida al Nutibara']);
      expect(find.text('Vuelta a la represa'), findsNothing);
    });

    testWidgets('al confirmar el nombre de una persona muestra solo sus '
        'rutas: no lo toma por un lugar', (tester) async {
      await montar(tester);
      await escribir(tester, 'luis');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      // Se preguntó, y "Luis" no es una zona.
      expect([for (final c in zonas.consultas) c.texto], ['luis']);
      expect(repositorio.busquedas.last.zona, isNull);
      expect(enPantalla(tester), ['Cerro de las tres cruces']);
      expect(find.byKey(RutasScreen.claveNotaZona), findsNothing);
      expect(find.byKey(RutasScreen.claveSinResultados), findsNothing);
    });
  });

  group('sin resultados (SCRUM-257, criterio 4 de HU-30)', () {
    Future<void> buscar(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
    }

    testWidgets('cuando termina de escribir sin coincidencias, lo dice y '
        'sugiere revisar lo escrito', (tester) async {
      await montar(tester);

      await buscar(tester, 'zzz');

      expect(find.text(RutasScreen.sinResultados), findsOneWidget);
      expect(find.textContaining('«zzz»'), findsOneWidget);
      expect(find.textContaining(RutasScreen.revisaLoEscrito), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
    });

    testWidgets('mientras sigue escribiendo todavía no lo dice', (
      tester,
    ) async {
      await montar(tester);

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), 'zzz');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(RutasScreen.claveSinResultados), findsNothing);

      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();

      expect(find.byKey(RutasScreen.claveSinResultados), findsOneWidget);

      // Tras una búsqueda vacía, el mensaje no se adelanta a la siguiente:
      // no dice que no hay nada con lo nuevo antes de haberlo buscado.
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), 'zzzy');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('«zzzy»'), findsNothing);

      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();

      expect(find.textContaining('«zzzy»'), findsOneWidget);
    });

    testWidgets('con varias palabras sugiere probar con menos', (tester) async {
      await montar(tester);

      await buscar(tester, 'subida zzz');

      expect(
        find.textContaining(RutasScreen.revisaLoEscritoVariasPalabras),
        findsOneWidget,
      );
    });

    testWidgets('antes de confirmar sugiere buscarlo como lugar; '
        'confirmado y sin lugar, ya no', (tester) async {
      await montar(tester);
      await buscar(tester, 'zzz');
      expect(find.textContaining(RutasScreen.buscaloComoLugar), findsOneWidget);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('no encontramos un lugar con ese nombre'),
        findsOneWidget,
      );
      expect(find.textContaining(RutasScreen.buscaloComoLugar), findsNothing);
      // Lo escrito puede estar mal: la sugerencia sigue.
      expect(find.textContaining(RutasScreen.revisaLoEscrito), findsOneWidget);
    });

    testWidgets('si el lugar existe pero no arranca ninguna ruta allá, lo '
        'dice', (tester) async {
      await montar(tester);
      await buscar(tester, 'envigado');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ni arranca en Envigado, Antioquia'),
        findsOneWidget,
      );
    });

    testWidgets('se lo anuncia al lector de pantalla, y otra vez si la '
        'siguiente búsqueda tampoco encuentra nada', (tester) async {
      final anuncios = escucharAnuncios(tester);
      await montar(tester);

      await buscar(tester, 'zzz');
      await buscar(tester, 'yyy');

      expect(anuncios, hasLength(2));
      expect(anuncios.first, startsWith('${RutasScreen.sinResultados}. '));
      expect(anuncios.first, contains('«zzz»'));
      expect(anuncios.last, contains('«yyy»'));
    });

    testWidgets('con resultados no anuncia nada', (tester) async {
      final anuncios = escucharAnuncios(tester);
      await montar(tester);

      await buscar(tester, 'nutibara');

      expect(anuncios, isEmpty);
    });

    testWidgets('al encontrar algo, el mensaje se va', (tester) async {
      await montar(tester);
      await buscar(tester, 'zzz');

      await buscar(tester, 'nutibara');

      expect(find.byKey(RutasScreen.claveSinResultados), findsNothing);
      expect(find.text('Subida al Nutibara'), findsOneWidget);
    });

    testWidgets('en la pantalla más estrecha con el texto más grande, el '
        'mensaje entero se puede leer sin desbordar', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.6);

      await buscar(tester, 'subida zzz');

      expect(tester.takeException(), isNull);
      expect(find.byKey(RutasScreen.claveSinResultados), findsOneWidget);
    });
  });

  group('la fila de rangos de distancia (SCRUM-273, criterio 1 de HU-37)', () {
    ChipFiltro chip(WidgetTester tester, RangoDistancia rango) =>
        tester.widget<ChipFiltro>(find.byKey(RutasScreen.claveRango(rango)));

    List<bool> activos(WidgetTester tester) => [
      for (final rango in RangoDistancia.values) chip(tester, rango).activo,
    ];

    Future<void> tocar(WidgetTester tester, RangoDistancia rango) async {
      await tocarChip(tester, RutasScreen.claveRango(rango));
    }

    testWidgets('ofrece los cuatro rangos, de la más corta a la más larga, '
        'en una sola línea con los chips de los demás filtros de la app', (
      tester,
    ) async {
      await montar(tester);

      final chips = find.descendant(
        of: find.byKey(RutasScreen.claveFiltroDistancia),
        matching: find.byType(ChipFiltro),
      );
      expect(
        [for (final chip in tester.widgetList<ChipFiltro>(chips)) chip.texto],
        ['Menos de 5 km', '5 a 10 km', '10 a 20 km', 'Más de 20 km'],
      );
      // En una línea, aunque no quepan: la fila se desliza (SCRUM-267).
      expect({
        for (final chip in chips.evaluate())
          tester.getTopLeft(find.byWidget(chip.widget)).dy,
      }, hasLength(1));
    });

    testWidgets('va entre la barra de búsqueda y la lista', (tester) async {
      await montar(tester);

      final fila = tester.getRect(find.byKey(RutasScreen.claveFiltroDistancia));
      expect(
        fila.top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(RutasScreen.claveBusqueda)).bottom,
        ),
      );
      expect(
        fila.bottom,
        lessThanOrEqualTo(altoDe(tester, RutasScreen.rotuloCercania)),
      );
    });

    testWidgets('empieza sin ninguno elegido', (tester) async {
      await montar(tester);

      expect(activos(tester), [false, false, false, false]);
    });

    testWidgets('tocar un rango lo marca, y tocarlo otra vez lo quita '
        '(criterio 4 de HU-37)', (tester) async {
      await montar(tester);

      await tocar(tester, RangoDistancia.de5a10);
      expect(activos(tester), [false, true, false, false]);

      await tocar(tester, RangoDistancia.de5a10);
      expect(activos(tester), [false, false, false, false]);
    });

    testWidgets('uno a la vez: elegir otro reemplaza al anterior', (
      tester,
    ) async {
      await montar(tester);

      await tocar(tester, RangoDistancia.menosDe5);
      await tocar(tester, RangoDistancia.masDe20);

      expect(activos(tester), [false, false, false, true]);
    });

    testWidgets('sigue a la vista mientras se busca, con lo elegido', (
      tester,
    ) async {
      await montar(tester);
      await tocar(tester, RangoDistancia.de10a20);

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), 'nutibara');
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(activos(tester), [false, false, true, false]);
    });

    testWidgets('un lector de pantalla sabe cuál está elegido', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);

      await tocar(tester, RangoDistancia.menosDe5);

      expect(
        tester.getSemantics(
          find.byKey(RutasScreen.claveRango(RangoDistancia.menosDe5)),
        ),
        isSemantics(label: 'Menos de 5 km', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(
          find.byKey(RutasScreen.claveRango(RangoDistancia.de5a10)),
        ),
        isSemantics(label: '5 a 10 km', isButton: true, isSelected: false),
      );
      semantica.dispose();
    });

    testWidgets('en la pantalla más estrecha con el texto grande no desborda, '
        'y deslizando la fila se llega a cada rango', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

      expect(tester.takeException(), isNull);
      for (final rango in RangoDistancia.values) {
        await tester.ensureVisible(find.byKey(RutasScreen.claveRango(rango)));
        await tester.pumpAndSettle();
        expect(
          find.byKey(RutasScreen.claveRango(rango)).hitTestable(),
          findsOneWidget,
          reason: rango.etiqueta,
        );
      }
    });
  });

  group('la fila de dificultades (SCRUM-267, criterio 1 de HU-36)', () {
    /// "Todas" y las tres dificultades, en el orden de la fila.
    const opciones = <Dificultad?>[null, ...Dificultad.values];

    List<bool> activas(WidgetTester tester) => [
      for (final opcion in opciones)
        tester
            .widget<ChipFiltro>(find.byKey(RutasScreen.claveDificultad(opcion)))
            .activo,
    ];

    Rect rectDe(WidgetTester tester, Key clave) =>
        tester.getRect(find.byKey(clave));

    testWidgets('ofrece «Todas» y las tres dificultades, en una sola línea, '
        'con los mismos chips que los rangos de distancia', (tester) async {
      await montar(tester);

      final chips = find.descendant(
        of: find.byKey(RutasScreen.claveFiltroDificultad),
        matching: find.byType(ChipFiltro),
      );
      expect(
        [for (final chip in tester.widgetList<ChipFiltro>(chips)) chip.texto],
        ['Todas', 'Fácil', 'Moderada', 'Difícil'],
      );
      expect({
        for (final chip in chips.evaluate())
          tester.getTopLeft(find.byWidget(chip.widget)).dy,
      }, hasLength(1));
    });

    testWidgets('va entre la barra de búsqueda y los rangos de distancia', (
      tester,
    ) async {
      await montar(tester);

      final fila = rectDe(tester, RutasScreen.claveFiltroDificultad);
      expect(
        fila.top,
        greaterThanOrEqualTo(rectDe(tester, RutasScreen.claveBusqueda).bottom),
      );
      expect(
        fila.bottom,
        lessThanOrEqualTo(rectDe(tester, RutasScreen.claveFiltroDistancia).top),
      );
    });

    testWidgets('empieza en «Todas»: sin dificultad elegida, eso es lo que '
        'se ve marcado', (tester) async {
      await montar(tester);

      expect(activas(tester), [true, false, false, false]);
      expect(dificultadElegida(tester), isNull);
    });

    testWidgets('tocar una la marca como activa, y «Todas» deja de estarlo '
        '(criterio 2 de HU-36)', (tester) async {
      await montar(tester);

      await elegirDificultad(tester, Dificultad.moderada);

      expect(activas(tester), [false, false, true, false]);
      expect(dificultadElegida(tester), Dificultad.moderada);
    });

    testWidgets('una a la vez: elegir otra reemplaza a la anterior', (
      tester,
    ) async {
      await montar(tester);

      await elegirDificultad(tester, Dificultad.facil);
      await elegirDificultad(tester, Dificultad.dificil);

      expect(activas(tester), [false, false, false, true]);
    });

    testWidgets('«Todas» quita la elegida (criterio 3 de HU-36)', (
      tester,
    ) async {
      await montar(tester);
      await elegirDificultad(tester, Dificultad.facil);

      await elegirDificultad(tester, null);

      expect(activas(tester), [true, false, false, false]);
      expect(dificultadElegida(tester), isNull);
    });

    testWidgets('tocar otra vez la elegida también la quita, como en la fila '
        'de distancia', (tester) async {
      await montar(tester);
      await elegirDificultad(tester, Dificultad.facil);

      await elegirDificultad(tester, Dificultad.facil);

      expect(activas(tester), [true, false, false, false]);
    });

    testWidgets('la dificultad y la distancia se eligen por separado', (
      tester,
    ) async {
      await montar(tester);

      await elegirDificultad(tester, Dificultad.moderada);
      await tocarChip(tester, RutasScreen.claveRango(RangoDistancia.de5a10));
      expect(activas(tester), [false, false, true, false]);

      // Quitar el rango no toca la dificultad.
      await tocarChip(tester, RutasScreen.claveRango(RangoDistancia.de5a10));
      expect(activas(tester), [false, false, true, false]);
    });

    testWidgets('un lector de pantalla sabe cuál está elegida', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);

      await elegirDificultad(tester, Dificultad.facil);

      expect(
        tester.getSemantics(
          find.byKey(RutasScreen.claveDificultad(Dificultad.facil)),
        ),
        isSemantics(label: 'Fácil', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.byKey(RutasScreen.claveDificultad(null))),
        isSemantics(label: 'Todas', isButton: true, isSelected: false),
      );
      semantica.dispose();
    });

    testWidgets('en la pantalla más estrecha con el texto más grande, las dos '
        'filas no desbordan y la lista conserva su espacio', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.6);

      expect(tester.takeException(), isNull);
      // Con dos filas que saltaban de línea, la lista se quedaba en nada.
      expect(
        rectDe(tester, RutasScreen.claveLista).height,
        greaterThanOrEqualTo(568 / 3),
      );
      for (final opcion in opciones) {
        await tester.ensureVisible(
          find.byKey(RutasScreen.claveDificultad(opcion)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(RutasScreen.claveDificultad(opcion)).hitTestable(),
          findsOneWidget,
        );
      }
    });
  });

  group('aplicar el filtro de distancia (SCRUM-274, criterio 2 de HU-37)', () {
    // La más cercana es la más larga: el filtro mira lo que mide cada ruta,
    // no lo lejos que queda.
    final larga = rutaDePrueba(
      id: 'larga',
      nombre: 'Vuelta a Santa Elena',
      estado: EstadoRuta.publicada,
      distanciaKm: 15,
    );
    final corta = rutaDePrueba(
      id: 'corta',
      nombre: 'Vuelta al parque',
      estado: EstadoRuta.publicada,
      distanciaKm: 3.2,
    );
    final media = rutaDePrueba(
      id: 'media',
      nombre: 'Subida al Volador',
      estado: EstadoRuta.publicada,
      distanciaKm: 7.5,
    );
    final sinDistancia = rutaDePrueba(
      id: 'sin-distancia',
      nombre: 'Paseo sin medir',
      estado: EstadoRuta.publicada,
      distanciaKm: null,
    );
    final otraCorta = rutaDePrueba(
      id: 'otra-corta',
      nombre: 'Vuelta a la manzana',
      estado: EstadoRuta.publicada,
      distanciaKm: 4.1,
    );
    final muyLarga = rutaDePrueba(
      id: 'muy-larga',
      nombre: 'Travesía a Guatapé',
      estado: EstadoRuta.publicada,
      distanciaKm: 32,
    );
    final todas = [larga, corta, media, sinDistancia, otraCorta, muyLarga];

    // Alta para que la lista construya todas las tarjetas: las que quedan
    // fuera de la pantalla no se construyen, y no se podrían contar.
    const alta = Size(390, 2600);

    setUp(() {
      repositorio = RutasRepositorioFalso(rutas: todas)
        ..rutasCercanas = [
          for (final (i, ruta) in todas.indexed)
            RutaCercana(ruta: ruta, distanciaKm: 0.5 + i),
        ];
    });

    List<String> enPantalla(WidgetTester tester) => [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.id,
    ];

    Future<void> elegir(WidgetTester tester, RangoDistancia rango) async {
      await tocarChip(tester, RutasScreen.claveRango(rango));
    }

    Future<void> buscar(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
    }

    bool elegido(WidgetTester tester, RangoDistancia rango) => tester
        .widget<ChipFiltro>(find.byKey(RutasScreen.claveRango(rango)))
        .activo;

    testWidgets('con un rango elegido, solo las que miden eso, en el orden '
        'por cercanía', (tester) async {
      await montar(tester, tamano: alta);
      expect(enPantalla(tester), [
        'larga',
        'corta',
        'media',
        'sin-distancia',
        'otra-corta',
        'muy-larga',
      ]);

      // La más cercana mide 15 km: no sale entre las de menos de 5. Y la que
      // no tiene distancia registrada no sale en ninguno.
      await elegir(tester, RangoDistancia.menosDe5);
      expect(enPantalla(tester), ['corta', 'otra-corta']);

      await elegir(tester, RangoDistancia.de5a10);
      expect(enPantalla(tester), ['media']);

      await elegir(tester, RangoDistancia.de10a20);
      expect(enPantalla(tester), ['larga']);

      await elegir(tester, RangoDistancia.masDe20);
      expect(enPantalla(tester), ['muy-larga']);

      // Sigue diciendo qué lista es.
      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
    });

    testWidgets('una ruta que la tarjeta muestra como "5 km" sale en "5 a 10 '
        'km", aunque mida un poco menos', (tester) async {
      final casiCinco = rutaDePrueba(
        id: 'casi-cinco',
        nombre: 'Casi cinco',
        estado: EstadoRuta.publicada,
        distanciaKm: 4.996,
      );
      repositorio = RutasRepositorioFalso(rutas: [casiCinco])
        ..rutasCercanas = [RutaCercana(ruta: casiCinco, distanciaKm: 1)];
      await montar(tester);
      expect(find.text('5 km'), findsOneWidget);

      await elegir(tester, RangoDistancia.de5a10);
      expect(enPantalla(tester), ['casi-cinco']);

      await elegir(tester, RangoDistancia.menosDe5);
      expect(enPantalla(tester), isEmpty);
    });

    testWidgets('quitarlo devuelve la lista como estaba, sin volver a '
        'consultarla (criterio 4 de HU-37)', (tester) async {
      await montar(tester, tamano: alta);
      final antes = enPantalla(tester);

      await elegir(tester, RangoDistancia.de5a10);
      await elegir(tester, RangoDistancia.masDe20);
      await elegir(tester, RangoDistancia.masDe20);

      expect(elegido(tester, RangoDistancia.masDe20), isFalse);
      expect(enPantalla(tester), antes);
      // Cambiar de rango tampoco consultó: se filtra lo que ya había.
      expect(repositorio.consultasCercanas, 1);
    });

    testWidgets('también filtra los resultados de una búsqueda, sin buscar '
        'otra vez', (tester) async {
      await montar(tester, tamano: alta);
      await buscar(tester, 'vuelta');
      expect(enPantalla(tester), ['larga', 'corta', 'otra-corta']);
      final busquedas = repositorio.busquedas.length;

      await elegir(tester, RangoDistancia.menosDe5);

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(enPantalla(tester), ['corta', 'otra-corta']);
      expect(repositorio.busquedas, hasLength(busquedas));
    });

    testWidgets('al borrar la búsqueda sigue elegido: vuelven las cercanas, '
        'filtradas', (tester) async {
      await montar(tester, tamano: alta);
      await elegir(tester, RangoDistancia.menosDe5);
      await buscar(tester, 'vuelta');

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), '');
      await tester.pumpAndSettle();

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(elegido(tester, RangoDistancia.menosDe5), isTrue);
      expect(enPantalla(tester), ['corta', 'otra-corta']);
    });

    testWidgets('también las más recientes, cuando no se sabe dónde está el '
        'usuario', (tester) async {
      await montar(tester, ubicacion: EstadoPermiso.denegado, tamano: alta);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);

      await elegir(tester, RangoDistancia.masDe20);

      expect(enPantalla(tester), ['muy-larga']);
      // El aviso del permiso sigue arriba: no tiene que ver con el filtro.
      expect(find.byType(AvisoPermisoUbicacion), findsOneWidget);
    });

    testWidgets('sigue elegido al volver del detalle de una ruta', (
      tester,
    ) async {
      await montar(tester, tamano: alta);
      await elegir(tester, RangoDistancia.menosDe5);

      await tester.tap(find.byKey(TarjetaRutaExplorar.claveDe('corta')));
      await tester.pumpAndSettle();
      expect(find.byType(DetalleRutaScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(elegido(tester, RangoDistancia.menosDe5), isTrue);
      expect(enPantalla(tester), ['corta', 'otra-corta']);
    });

    testWidgets('al cambiar de rango la lista vuelve arriba', (tester) async {
      final muchas = [
        for (var i = 0; i < 10; i++)
          rutaDePrueba(
            id: 'r$i',
            nombre: 'Ruta $i',
            estado: EstadoRuta.publicada,
            distanciaKm: 3,
          ),
      ];
      repositorio = RutasRepositorioFalso(rutas: muchas)
        ..rutasCercanas = [
          for (final (i, ruta) in muchas.indexed)
            RutaCercana(ruta: ruta, distanciaKm: i + 1.0),
        ];
      await montar(tester);

      double desplazamiento() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(RutasScreen.claveLista),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;

      Future<void> bajar() async {
        await tester.drag(
          find.byKey(RutasScreen.claveLista),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();
        expect(desplazamiento(), greaterThan(0));
      }

      // Todas miden 3 km: la lista filtrada es igual de larga, y aun así
      // empieza arriba. Y al quitar el filtro, también.
      await bajar();
      await elegir(tester, RangoDistancia.menosDe5);
      expect(desplazamiento(), 0);

      await bajar();
      await elegir(tester, RangoDistancia.menosDe5);
      expect(desplazamiento(), 0);
    });
  });

  group('si el filtro deja la lista vacía (SCRUM-274)', () {
    final corta = rutaDePrueba(
      id: 'corta',
      nombre: 'Vuelta al parque',
      estado: EstadoRuta.publicada,
      distanciaKm: 3.2,
    );
    final media = rutaDePrueba(
      id: 'media',
      nombre: 'Subida al Volador',
      estado: EstadoRuta.publicada,
      distanciaKm: 7.5,
    );

    setUp(() {
      repositorio = RutasRepositorioFalso(rutas: [corta, media])
        ..rutasCercanas = [
          RutaCercana(ruta: corta, distanciaKm: 0.8),
          RutaCercana(ruta: media, distanciaKm: 1.5),
        ];
    });

    Future<void> elegir(WidgetTester tester, RangoDistancia rango) async {
      await tocarChip(tester, RutasScreen.claveRango(rango));
    }

    Future<void> buscar(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
    }

    test('el mensaje nombra el rango como se lee en una frase', () {
      expect(
        [
          for (final rango in RangoDistancia.values)
            RutasScreen.sinRutasCon(FiltrosRutas(distancia: rango)),
        ],
        [
          'Ninguna ruta de menos de 5 km',
          'Ninguna ruta de 5 a 10 km',
          'Ninguna ruta de 10 a 20 km',
          'Ninguna ruta de más de 20 km',
        ],
      );
    });

    testWidgets('lo dice debajo del rótulo, y deja quitar el filtro', (
      tester,
    ) async {
      await montar(tester);
      await elegir(tester, RangoDistancia.masDe20);

      const titulo = 'Ninguna ruta de más de 20 km';
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
      expect(find.text(titulo), findsOneWidget);
      expect(find.text(RutasScreen.pruebaOtroRango), findsOneWidget);
      expect(
        altoDe(tester, RutasScreen.rotuloCercania),
        lessThan(altoDe(tester, titulo)),
      );

      await tester.tap(find.byKey(RutasScreen.claveQuitarFiltros));
      await tester.pumpAndSettle();

      expect(find.byKey(RutasScreen.claveSinRutasConFiltros), findsNothing);
      expect(
        tester
            .widget<ChipFiltro>(
              find.byKey(RutasScreen.claveRango(RangoDistancia.masDe20)),
            )
            .activo,
        isFalse,
      );
      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
    });

    testWidgets('con una búsqueda, lo dice debajo de los resultados: la '
        'búsqueda sí encontró', (tester) async {
      await montar(tester);
      await buscar(tester, 'vuelta');

      await elegir(tester, RangoDistancia.de5a10);

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(find.text('Ninguna ruta de 5 a 10 km'), findsOneWidget);
      expect(find.byKey(RutasScreen.claveSinResultados), findsNothing);
    });

    testWidgets('si no hay ninguna ruta cerca, lo dice sin culpar al filtro', (
      tester,
    ) async {
      repositorio = RutasRepositorioFalso()..rutasCercanas = const [];
      await montar(tester);

      await elegir(tester, RangoDistancia.menosDe5);

      expect(find.byKey(RutasScreen.claveSinRutasCerca), findsOneWidget);
      expect(find.byKey(RutasScreen.claveSinRutasConFiltros), findsNothing);
    });

    testWidgets('si la búsqueda no encontró nada, lo dice la búsqueda', (
      tester,
    ) async {
      await montar(tester);
      await elegir(tester, RangoDistancia.menosDe5);

      await buscar(tester, 'zzz');

      expect(find.byKey(RutasScreen.claveSinResultados), findsOneWidget);
      expect(find.byKey(RutasScreen.claveSinRutasConFiltros), findsNothing);
    });

    testWidgets('en la pantalla más estrecha con el texto grande no desborda', (
      tester,
    ) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

      await elegir(tester, RangoDistancia.masDe20);

      expect(tester.takeException(), isNull);
      expect(find.byKey(RutasScreen.claveSinRutasConFiltros), findsOneWidget);
    });
  });

  group('combinar los dos filtros (SCRUM-275, criterio 3 de HU-37)', () {
    final facilCorta = rutaDePrueba(
      id: 'facil-corta',
      nombre: 'Vuelta al parque',
      estado: EstadoRuta.publicada,
      distanciaKm: 3.2,
      dificultad: Dificultad.facil,
    );
    final facilLarga = rutaDePrueba(
      id: 'facil-larga',
      nombre: 'Vuelta a Santa Elena',
      estado: EstadoRuta.publicada,
      distanciaKm: 15,
      dificultad: Dificultad.facil,
    );
    final moderadaMedia = rutaDePrueba(
      id: 'moderada-media',
      nombre: 'Subida al Volador',
      estado: EstadoRuta.publicada,
      distanciaKm: 7.5,
      dificultad: Dificultad.moderada,
    );
    final dificilCorta = rutaDePrueba(
      id: 'dificil-corta',
      nombre: 'Escaleras de la 70',
      estado: EstadoRuta.publicada,
      distanciaKm: 2.1,
      dificultad: Dificultad.dificil,
    );
    final sinClasificar = rutaDePrueba(
      id: 'sin-clasificar',
      nombre: 'Vuelta a la manzana',
      estado: EstadoRuta.publicada,
      distanciaKm: 4.1,
    );
    final todas = [
      facilCorta,
      facilLarga,
      moderadaMedia,
      dificilCorta,
      sinClasificar,
    ];

    // Alta para que la lista construya todas las tarjetas.
    const alta = Size(390, 2600);

    setUp(() {
      repositorio = RutasRepositorioFalso(rutas: todas)
        ..rutasCercanas = [
          for (final (i, ruta) in todas.indexed)
            RutaCercana(ruta: ruta, distanciaKm: 0.5 + i),
        ];
    });

    List<String> enPantalla(WidgetTester tester) => [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.id,
    ];

    Future<void> elegirRango(WidgetTester tester, RangoDistancia rango) async {
      await tocarChip(tester, RutasScreen.claveRango(rango));
    }

    Future<void> buscar(WidgetTester tester, String texto) async {
      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), texto);
      await tester.pump(esperaBusquedaRutas);
      await tester.pumpAndSettle();
    }

    testWidgets('con las dos elegidas, solo las que cumplen las dos, en el '
        'orden por cercanía', (tester) async {
      await montar(tester, tamano: alta);

      await elegirDificultad(tester, Dificultad.facil);
      expect(enPantalla(tester), ['facil-corta', 'facil-larga']);

      await elegirRango(tester, RangoDistancia.menosDe5);
      expect(enPantalla(tester), ['facil-corta']);

      await elegirRango(tester, RangoDistancia.de10a20);
      expect(enPantalla(tester), ['facil-larga']);
      // La tarjeta dice la dificultad por la que pasó el filtro.
      expect(
        find.descendant(
          of: find.byType(TarjetaRutaExplorar),
          matching: find.text('Fácil'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('una sin clasificar sale con la distancia, pero no con una '
        'dificultad', (tester) async {
      await montar(tester, tamano: alta);

      await elegirRango(tester, RangoDistancia.menosDe5);
      expect(enPantalla(tester), [
        'facil-corta',
        'dificil-corta',
        'sin-clasificar',
      ]);

      await elegirDificultad(tester, Dificultad.facil);
      expect(enPantalla(tester), ['facil-corta']);
    });

    testWidgets('quitar uno deja el otro, sin volver a consultar', (
      tester,
    ) async {
      await montar(tester, tamano: alta);
      await elegirDificultad(tester, Dificultad.facil);
      await elegirRango(tester, RangoDistancia.menosDe5);

      // Tocar otra vez el rango lo quita: quedan todas las fáciles.
      await elegirRango(tester, RangoDistancia.menosDe5);
      expect(enPantalla(tester), ['facil-corta', 'facil-larga']);

      await elegirDificultad(tester, null);
      expect(enPantalla(tester), [
        'facil-corta',
        'facil-larga',
        'moderada-media',
        'dificil-corta',
        'sin-clasificar',
      ]);
      expect(repositorio.consultasCercanas, 1);
    });

    testWidgets('también sobre los resultados de una búsqueda, sin buscar '
        'otra vez', (tester) async {
      await montar(tester, tamano: alta);
      await buscar(tester, 'vuelta');
      expect(enPantalla(tester), [
        'facil-corta',
        'facil-larga',
        'sin-clasificar',
      ]);
      final busquedas = repositorio.busquedas.length;

      await elegirDificultad(tester, Dificultad.facil);
      await elegirRango(tester, RangoDistancia.menosDe5);

      expect(find.text(RutasScreen.rotuloResultados), findsOneWidget);
      expect(enPantalla(tester), ['facil-corta']);
      expect(repositorio.busquedas, hasLength(busquedas));
    });

    testWidgets('la dificultad elegida sigue al buscar y al borrar la '
        'búsqueda', (tester) async {
      await montar(tester, tamano: alta);
      await elegirDificultad(tester, Dificultad.facil);

      // Mientras llega la búsqueda, la lista se cambia por un indicador.
      await buscar(tester, 'vuelta');
      expect(enPantalla(tester), ['facil-corta', 'facil-larga']);

      await tester.enterText(find.byKey(RutasScreen.claveBusqueda), '');
      await tester.pumpAndSettle();

      expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      expect(dificultadElegida(tester), Dificultad.facil);
      expect(enPantalla(tester), ['facil-corta', 'facil-larga']);
    });

    testWidgets('al cambiar la dificultad, la lista también vuelve arriba', (
      tester,
    ) async {
      final muchas = [
        for (var i = 0; i < 10; i++)
          rutaDePrueba(
            id: 'r$i',
            nombre: 'Ruta $i',
            estado: EstadoRuta.publicada,
            distanciaKm: 3,
            dificultad: Dificultad.facil,
          ),
      ];
      repositorio = RutasRepositorioFalso(rutas: muchas)
        ..rutasCercanas = [
          for (final (i, ruta) in muchas.indexed)
            RutaCercana(ruta: ruta, distanciaKm: i + 1.0),
        ];
      await montar(tester);

      double desplazamiento() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(RutasScreen.claveLista),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .pixels;

      await tester.drag(
        find.byKey(RutasScreen.claveLista),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(desplazamiento(), greaterThan(0));

      // Todas son fáciles: la lista filtrada es igual de larga.
      await elegirDificultad(tester, Dificultad.facil);
      expect(desplazamiento(), 0);
    });
  });

  group('sin resultados con los filtros (SCRUM-275, criterio 5 de HU-37)', () {
    final facilCorta = rutaDePrueba(
      id: 'facil-corta',
      nombre: 'Vuelta al parque',
      estado: EstadoRuta.publicada,
      distanciaKm: 3.2,
      dificultad: Dificultad.facil,
    );
    final moderadaMedia = rutaDePrueba(
      id: 'moderada-media',
      nombre: 'Subida al Volador',
      estado: EstadoRuta.publicada,
      distanciaKm: 7.5,
      dificultad: Dificultad.moderada,
    );
    final rutas = [facilCorta, moderadaMedia];

    setUp(() {
      repositorio = RutasRepositorioFalso(rutas: rutas)
        ..rutasCercanas = [
          RutaCercana(ruta: facilCorta, distanciaKm: 0.8),
          RutaCercana(ruta: moderadaMedia, distanciaKm: 1.5),
        ];
    });

    Future<void> elegirRango(WidgetTester tester, RangoDistancia rango) async {
      await tocarChip(tester, RutasScreen.claveRango(rango));
    }

    bool elegido(WidgetTester tester, RangoDistancia rango) => tester
        .widget<ChipFiltro>(find.byKey(RutasScreen.claveRango(rango)))
        .activo;

    test('el título dice la combinación que no tiene rutas', () {
      expect(
        RutasScreen.sinRutasCon(
          const FiltrosRutas(
            dificultad: Dificultad.facil,
            distancia: RangoDistancia.de5a10,
          ),
        ),
        'Ninguna ruta fácil de 5 a 10 km',
      );
      expect(
        RutasScreen.sinRutasCon(
          const FiltrosRutas(
            dificultad: Dificultad.moderada,
            distancia: RangoDistancia.masDe20,
          ),
        ),
        'Ninguna ruta moderada de más de 20 km',
      );
      expect(
        RutasScreen.sinRutasCon(
          const FiltrosRutas(dificultad: Dificultad.dificil),
        ),
        'Ninguna ruta difícil',
      );
    });

    test('con los dos, dice cuál deja fuera las rutas', () {
      String queHacer(Dificultad dificultad, RangoDistancia rango) =>
          RutasScreen.queHacerSinRutasCon(
            FiltrosRutas(dificultad: dificultad, distancia: rango),
            rutas,
          );

      // Hay fáciles y hay de 5 a 10 km, pero ninguna fácil de 5 a 10 km.
      expect(
        queHacer(Dificultad.facil, RangoDistancia.de5a10),
        'Hay rutas fáciles y rutas de 5 a 10 km, pero ninguna que cumpla las '
        'dos. Prueba quitando uno de los filtros.',
      );
      // Lo que falta es el rango.
      expect(
        queHacer(Dificultad.facil, RangoDistancia.masDe20),
        'Hay rutas fáciles, pero ninguna de más de 20 km. Prueba con otro '
        'rango.',
      );
      // Lo que falta es la dificultad.
      expect(
        queHacer(Dificultad.dificil, RangoDistancia.de5a10),
        'Hay rutas de 5 a 10 km, pero ninguna difícil. Prueba con otra '
        'dificultad.',
      );
      // Faltan los dos.
      expect(
        queHacer(Dificultad.dificil, RangoDistancia.masDe20),
        'No hay rutas difíciles ni de más de 20 km. Prueba con otros filtros o '
        'quítalos para verlas todas.',
      );
    });

    test('con uno solo, sugiere probar con otro valor de ese filtro', () {
      expect(
        RutasScreen.queHacerSinRutasCon(
          const FiltrosRutas(dificultad: Dificultad.dificil),
          rutas,
        ),
        RutasScreen.pruebaOtraDificultad,
      );
      expect(
        RutasScreen.queHacerSinRutasCon(
          const FiltrosRutas(distancia: RangoDistancia.masDe20),
          rutas,
        ),
        RutasScreen.pruebaOtroRango,
      );
    });

    testWidgets('lo dice debajo del rótulo, y «Quitar los filtros» quita los '
        'dos', (tester) async {
      await montar(tester);
      await elegirDificultad(tester, Dificultad.facil);
      await elegirRango(tester, RangoDistancia.de5a10);

      const titulo = 'Ninguna ruta fácil de 5 a 10 km';
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
      expect(find.text(titulo), findsOneWidget);
      expect(
        find.textContaining('pero ninguna que cumpla las dos'),
        findsOneWidget,
      );
      expect(
        altoDe(tester, RutasScreen.rotuloCercania),
        lessThan(altoDe(tester, titulo)),
      );
      expect(find.text('Quitar los filtros'), findsOneWidget);

      await tester.tap(find.byKey(RutasScreen.claveQuitarFiltros));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
      expect(elegido(tester, RangoDistancia.de5a10), isFalse);
      expect(dificultadElegida(tester), isNull);
    });

    testWidgets('con un filtro solo, el botón dice «Quitar el filtro»', (
      tester,
    ) async {
      await montar(tester);
      await elegirDificultad(tester, Dificultad.dificil);

      expect(find.text('Ninguna ruta difícil'), findsOneWidget);
      expect(find.text(RutasScreen.pruebaOtraDificultad), findsOneWidget);
      expect(find.text('Quitar el filtro'), findsOneWidget);

      await tester.tap(find.byKey(RutasScreen.claveQuitarFiltros));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaRutaExplorar), findsNWidgets(2));
      expect(dificultadElegida(tester), isNull);
    });

    testWidgets('se le anuncia al lector de pantalla, y otra vez si cambia '
        'la combinación', (tester) async {
      final anuncios = escucharAnuncios(tester);
      await montar(tester);

      // Hay fáciles: no hay nada que anunciar.
      await elegirDificultad(tester, Dificultad.facil);
      expect(anuncios, isEmpty);

      await elegirRango(tester, RangoDistancia.masDe20);
      await elegirRango(tester, RangoDistancia.de10a20);

      expect(anuncios, [
        'Ninguna ruta fácil de más de 20 km. Hay rutas fáciles, pero ninguna '
            'de más de 20 km. Prueba con otro rango.',
        'Ninguna ruta fácil de 10 a 20 km. Hay rutas fáciles, pero ninguna de '
            '10 a 20 km. Prueba con otro rango.',
      ]);
    });

    testWidgets('también con la distancia sola (SCRUM-274)', (tester) async {
      final anuncios = escucharAnuncios(tester);
      await montar(tester);

      await elegirRango(tester, RangoDistancia.masDe20);

      expect(anuncios, [
        'Ninguna ruta de más de 20 km. ${RutasScreen.pruebaOtroRango}',
      ]);
    });

    testWidgets('en la pantalla más estrecha con el texto grande no desborda', (
      tester,
    ) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

      await elegirDificultad(tester, Dificultad.dificil);
      await elegirRango(tester, RangoDistancia.masDe20);

      expect(tester.takeException(), isNull);
      expect(find.byKey(RutasScreen.claveSinRutasConFiltros), findsOneWidget);
    });
  });

  group('aplicar el filtro de dificultad (SCRUM-268, criterio 2 de HU-36)', () {
    final facilCorta = rutaDePrueba(
      id: 'facil-corta',
      nombre: 'Vuelta al parque',
      estado: EstadoRuta.publicada,
      distanciaKm: 3.2,
      dificultad: Dificultad.facil,
    );
    final moderadaMedia = rutaDePrueba(
      id: 'moderada-media',
      nombre: 'Subida al Volador',
      estado: EstadoRuta.publicada,
      distanciaKm: 7.5,
      dificultad: Dificultad.moderada,
    );
    final facilLarga = rutaDePrueba(
      id: 'facil-larga',
      nombre: 'Vuelta a Santa Elena',
      estado: EstadoRuta.publicada,
      distanciaKm: 15,
      dificultad: Dificultad.facil,
    );
    final sinClasificar = rutaDePrueba(
      id: 'sin-clasificar',
      nombre: 'Vuelta a la manzana',
      estado: EstadoRuta.publicada,
      distanciaKm: 4.1,
    );
    final dificilCorta = rutaDePrueba(
      id: 'dificil-corta',
      nombre: 'Escaleras de la 70',
      estado: EstadoRuta.publicada,
      distanciaKm: 2.1,
      dificultad: Dificultad.dificil,
    );
    final todas = [
      facilCorta,
      moderadaMedia,
      facilLarga,
      sinClasificar,
      dificilCorta,
    ];

    // Alta para que la lista construya todas las tarjetas.
    const alta = Size(390, 2600);

    List<RutaCercana> cercanas(List<Ruta> rutas) => [
      for (final (i, ruta) in rutas.indexed)
        RutaCercana(ruta: ruta, distanciaKm: 0.5 + i),
    ];

    setUp(() {
      repositorio = RutasRepositorioFalso(rutas: todas)
        ..rutasCercanas = cercanas(todas);
    });

    List<String> enPantalla(WidgetTester tester) => [
      for (final tarjeta in tester.widgetList<TarjetaRutaExplorar>(
        find.byType(TarjetaRutaExplorar),
      ))
        tarjeta.ruta.id,
    ];

    bool marcada(WidgetTester tester, Dificultad? dificultad) => tester
        .widget<ChipFiltro>(find.byKey(RutasScreen.claveDificultad(dificultad)))
        .activo;

    /// Desliza la lista hacia abajo, como el usuario para recargarla: media
    /// lista, porque el indicador pide arrastrar un cuarto de lo que mide.
    Future<void> recargar(WidgetTester tester) async {
      final lista = find.byKey(RutasScreen.claveLista);
      await tester.fling(
        lista,
        Offset(0, tester.getSize(lista).height / 2),
        1000,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('con una dificultad elegida, solo las de esa dificultad, en el '
        'orden por cercanía y con su chip marcado', (tester) async {
      await montar(tester, tamano: alta);

      const esperadas = {
        Dificultad.facil: ['facil-corta', 'facil-larga'],
        Dificultad.moderada: ['moderada-media'],
        Dificultad.dificil: ['dificil-corta'],
      };
      for (final MapEntry(key: dificultad, value: rutas) in esperadas.entries) {
        await elegirDificultad(tester, dificultad);

        expect(enPantalla(tester), rutas, reason: dificultad.etiqueta);
        expect(marcada(tester, dificultad), isTrue);
        expect(marcada(tester, null), isFalse);
        expect(find.text(RutasScreen.rotuloCercania), findsOneWidget);
      }
    });

    testWidgets('la tarjeta de cada una dice esa dificultad', (tester) async {
      await montar(tester, tamano: alta);

      await elegirDificultad(tester, Dificultad.facil);

      expect(
        find.descendant(
          of: find.byType(TarjetaRutaExplorar),
          matching: find.text('Fácil'),
        ),
        findsNWidgets(2),
      );
      expect(find.text(TarjetaRutaExplorar.sinDificultad), findsNothing);
    });

    testWidgets('una ruta sin clasificar no sale con ninguna dificultad, y '
        'vuelve con «Todas»', (tester) async {
      await montar(tester, tamano: alta);

      for (final dificultad in Dificultad.values) {
        await elegirDificultad(tester, dificultad);
        expect(
          enPantalla(tester),
          isNot(contains('sin-clasificar')),
          reason: dificultad.etiqueta,
        );
      }

      await elegirDificultad(tester, null);
      expect(enPantalla(tester), contains('sin-clasificar'));
    });

    testWidgets('pasar de una a otra refresca la lista al instante, sin '
        'volver a consultar la base', (tester) async {
      await montar(tester, tamano: alta);
      expect(repositorio.consultasCercanas, 1);

      await elegirDificultad(tester, Dificultad.facil);
      await elegirDificultad(tester, Dificultad.moderada);
      await elegirDificultad(tester, Dificultad.dificil);
      await elegirDificultad(tester, null);

      expect(enPantalla(tester), [for (final ruta in todas) ruta.id]);
      expect(repositorio.consultasCercanas, 1);
    });

    testWidgets('al recargar con una dificultad elegida, lo nuevo llega ya '
        'filtrado y la dificultad sigue elegida', (tester) async {
      await montar(tester, tamano: alta);
      await elegirDificultad(tester, Dificultad.facil);

      // Mientras tanto se publicaron dos rutas más, una fácil y una
      // moderada, y la nueva fácil es la más cercana.
      final nuevaFacil = rutaDePrueba(
        id: 'nueva-facil',
        nombre: 'Vuelta al lago',
        estado: EstadoRuta.publicada,
        distanciaKm: 6,
        dificultad: Dificultad.facil,
      );
      final nuevaModerada = rutaDePrueba(
        id: 'nueva-moderada',
        nombre: 'Loma del Indio',
        estado: EstadoRuta.publicada,
        distanciaKm: 9,
        dificultad: Dificultad.moderada,
      );
      repositorio.rutasCercanas = cercanas([
        nuevaFacil,
        ...todas,
        nuevaModerada,
      ]);

      await recargar(tester);

      expect(repositorio.consultasCercanas, 2);
      expect(marcada(tester, Dificultad.facil), isTrue);
      expect(enPantalla(tester), ['nueva-facil', 'facil-corta', 'facil-larga']);
    });

    testWidgets('también filtra las más recientes, cuando no se sabe dónde '
        'está el usuario', (tester) async {
      await montar(tester, ubicacion: EstadoPermiso.denegado, tamano: alta);
      expect(find.text(RutasScreen.rotuloRecientes), findsOneWidget);

      await elegirDificultad(tester, Dificultad.moderada);

      expect(enPantalla(tester), ['moderada-media']);
      expect(find.byType(AvisoPermisoUbicacion), findsOneWidget);
    });
  });
}
