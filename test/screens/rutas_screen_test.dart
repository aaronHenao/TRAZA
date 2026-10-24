import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_cercana.dart';
import 'package:traza/models/zona.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/publicar_ruta_screen.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/screens/rutas/seccion_rutas.dart';
import 'package:traza/services/busqueda_rutas_provider.dart';
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
      await tester.tap(find.byKey(RutasScreen.claveRango(rango)));
      await tester.pumpAndSettle();
    }

    testWidgets('ofrece los cuatro rangos, de la más corta a la más larga, '
        'con los chips de los demás filtros de la app', (tester) async {
      await montar(tester);

      final fila = find.byKey(RutasScreen.claveFiltroDistancia);
      expect(tester.widget(fila), isA<FilaChips>());
      expect(
        [
          for (final chip in tester.widgetList<ChipFiltro>(
            find.descendant(of: fila, matching: find.byType(ChipFiltro)),
          ))
            chip.texto,
        ],
        ['Menos de 5 km', '5 a 10 km', '10 a 20 km', 'Más de 20 km'],
      );
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

    testWidgets('en la pantalla más estrecha con el texto grande, saltan de '
        'línea sin desbordar y se pueden tocar todos', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.3);

      expect(tester.takeException(), isNull);
      for (final rango in RangoDistancia.values) {
        expect(
          find.byKey(RutasScreen.claveRango(rango)).hitTestable(),
          findsOneWidget,
        );
      }
    });
  });
}
