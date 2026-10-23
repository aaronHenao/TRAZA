import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_cercana.dart';
import 'package:traza/screens/rutas/rutas_screen.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/ancho_contenido.dart';
import 'package:traza/widgets/aviso_permiso_ubicacion.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
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

/// Pruebas de Explorar rutas, la sección de Rutas (SCRUM-246).
///
/// Reemplaza a la pantalla provisional de SCRUM-284: ahora lista las rutas
/// de la comunidad, de la más cercana a la más lejana.
void main() {
  late _MockPermisosService permisos;
  late FuenteUbicacionFalsa fuente;
  late RutasRepositorioFalso repositorio;

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
        GoRoute(path: RutasScreen.ruta, builder: (_, _) => const RutasScreen()),
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

      expect(find.text('Todavía no hay rutas para mostrarte'), findsOneWidget);
      expect(find.byType(TarjetaRutaExplorar), findsNothing);
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
}
