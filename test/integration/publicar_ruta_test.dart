// Pruebas de integración de la publicación de rutas (SCRUM-241): del resumen
// del entrenamiento al formulario, de ahí a la revisión, y de la aprobación
// al aviso en la bandeja y a la ruta visible en el foro con su autoría.
//
// Monta las pantallas de verdad y las rutas tal como las arma `main.dart`.
// Solo se reemplaza lo que necesita red.
//
// Lo que estas pruebas NO prueban: que la base cree la notificación al
// aprobar la ruta. Eso lo hace el trigger de `0033_aviso_de_ruta_publicada`
// y no se puede ejecutar desde aquí; lo que se comprueba es que, cuando el
// aviso existe, el usuario lo encuentra. La comprobación del trigger está
// escrita al final de esa migración.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/notificacion.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/foro/foro_screen.dart';
import 'package:traza/screens/notificaciones/notificaciones_screen.dart';
import 'package:traza/screens/rutas/publicar_ruta_screen.dart';
import 'package:traza/screens/summary/resumen_screen.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/cambios_notificaciones.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/notificaciones_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/foro_repository_falso.dart';
import '../utiles/fuente_cambios_foro_falsa.dart';
import '../utiles/fuente_cambios_notificaciones_falsa.dart';
import '../utiles/niveles_falso.dart';
import '../utiles/notificaciones_falso.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

void main() {
  final ahora = DateTime(2026, 10, 17, 12);

  // ~1,1 km, con un punto cada ~11 m. Tiene que ser bastante más largo que
  // los dos radios de privacidad (RNF-04) o apenas quedaría trazo que
  // publicar.
  final recorrido = [
    for (var i = 0; i <= 100; i++)
      PuntoGps(
        latitud: 6.2442 + i / 10000,
        longitud: -75.5812,
        capturadoEn: DateTime(2026, 10, 17, 7).add(Duration(seconds: i * 5)),
      ),
  ];

  final entrenamiento = ResumenEntrenamiento(
    entrenamientoId: 'e-123',
    nombreActividad: 'Trote',
    fechaFin: DateTime(2026, 10, 17, 8),
    duracion: const Duration(minutes: 32),
    distanciaMetros: 5230.5,
    puntos: recorrido,
  );

  late RutasRepositorioFalso rutas;
  late NotificacionesFalso avisos;

  Future<void> abrirResumen(
    WidgetTester tester, {
    List<Ruta> publicadas = const [],
    List<Notificacion> notificaciones = const [],
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    rutas = RutasRepositorioFalso(rutas: publicadas);
    avisos = NotificacionesFalso(notificaciones: notificaciones);

    final router = GoRouter(
      initialLocation: '/resumen/e-123',
      initialExtra: entrenamiento,
      routes: [
        GoRoute(
          path: '/resumen',
          builder: (_, estado) => ResumenScreen.desdeRuta(estado),
          routes: [
            GoRoute(
              path: ':entrenamientoId',
              builder: (_, estado) => ResumenScreen.desdeRuta(estado),
            ),
          ],
        ),
        GoRoute(
          path: PublicarRutaScreen.ruta,
          builder: (_, estado) => PublicarRutaScreen(
            resumen: estado.extra as ResumenEntrenamiento?,
          ),
        ),
        GoRoute(path: ForoScreen.ruta, builder: (_, _) => const ForoScreen()),
        GoRoute(
          path: NotificacionesScreen.ruta,
          builder: (_, _) => const NotificacionesScreen(),
        ),
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Portada')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relojProvider.overrideWithValue(() => ahora),
          usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
          rutasRepositoryProvider.overrideWithValue(rutas),
          notificacionesRepositoryProvider.overrideWithValue(avisos),
          fuenteCambiosNotificacionesProvider.overrideWithValue(
            FuenteCambiosNotificacionesFalsa(),
          ),
          foroRepositoryProvider.overrideWithValue(
            ForoRepositorioFalso(ahora: ahora),
          ),
          fuenteCambiosForoProvider.overrideWithValue(FuenteCambiosForoFalsa()),
          entrenamientoRepositoryProvider.overrideWithValue(
            _EntrenamientosFalso(),
          ),
          experienciaRepositoryProvider.overrideWithValue(ExperienciaFalsa()),
          nivelesRepositoryProvider.overrideWithValue(
            NivelesFalso(
              catalogo: const [
                Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100),
              ],
            ),
          ),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('del resumen a la revision: la ruta queda esperando aprobacion', (
    tester,
  ) async {
    await abrirResumen(tester);

    // Criterio 1: se publica el recorrido del entrenamiento que se acaba de
    // terminar, desde donde ya se está viendo.
    await tester.tap(find.byKey(ResumenScreen.clavePublicarRuta));
    await tester.pumpAndSettle();

    expect(find.text('Publicar ruta'), findsWidgets);
    expect(
      find.text('5.23 km · la distancia que llevará tu ruta'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(PublicarRutaScreen.claveNombre),
      'Vuelta al Parque Norte',
    );
    await tester.enterText(
      find.byKey(PublicarRutaScreen.claveDescripcion),
      'Plana y con sombra.',
    );
    await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
    await tester.pumpAndSettle();

    // Lo que salió hacia la base: el entrenamiento, lo escrito y el trazado.
    final enviada = rutas.recibida!;
    expect(enviada.entrenamientoId, 'e-123');
    expect(enviada.nombre, 'Vuelta al Parque Norte');
    expect(enviada.descripcion, 'Plana y con sombra.');
    // Menos puntos que el recorrido: los extremos no se publican (RNF-04).
    expect(enviada.trazado.length, lessThan(recorrido.length));
    expect(enviada.trazado.first.latitud, isNot(recorrido.first.latitud));
    expect(enviada.recorridoCompleto, isFalse);

    // Y lo que ve el autor: que no está publicada, que está en revisión.
    expect(find.text(PublicacionRuta.enRevision), findsOneWidget);
    expect(find.text('Resumen'), findsOneWidget);
  });

  testWidgets('sin nombre no se publica y se dice que falta (criterio 3)', (
    tester,
  ) async {
    await abrirResumen(tester);

    await tester.tap(find.byKey(ResumenScreen.clavePublicarRuta));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(PublicarRutaScreen.clavePublicar));
    await tester.pumpAndSettle();

    expect(find.text('Ponle un nombre a tu ruta.'), findsOneWidget);
    expect(rutas.creaciones, 0);
    // Sigue en el formulario, con lo que ya había escrito.
    expect(find.byKey(PublicarRutaScreen.clavePublicar), findsOneWidget);
  });

  testWidgets('aprobada: el autor se entera y la comunidad la ve', (
    tester,
  ) async {
    // Una ruta de OTRA persona, para mirarla como la mira la comunidad: el
    // criterio 4 habla de lo que ve quien no la publico.
    final deOtra = Ruta(
      id: 'ruta-2',
      autorId: 'usuario-9',
      autorNombre: 'Ana',
      nombre: 'Cerro Pan de Azucar',
      estado: EstadoRuta.publicada,
      distanciaKm: 5.23,
      fechaCreacion: DateTime(2026, 10, 17, 9),
      fechaPublicacion: DateTime(2026, 10, 17, 10),
    );

    await abrirResumen(
      tester,
      publicadas: [deOtra],
      notificaciones: [
        notificacionDePrueba(
          titulo: 'Tu ruta ya está publicada',
          mensaje:
              '«Vuelta al Parque Norte» ya la puede ver toda la comunidad.',
          entidadId: 'ruta-1',
          fechaCreacion: DateTime(2026, 10, 17, 10),
        ),
      ],
    );

    // Criterio 2: el autor encuentra el aviso en su bandeja.
    final router = GoRouter.of(tester.element(find.byType(ResumenScreen)));
    router.push(NotificacionesScreen.ruta);
    await tester.pumpAndSettle();

    expect(find.text('Tu ruta ya está publicada'), findsOneWidget);
    expect(
      find.text('«Vuelta al Parque Norte» ya la puede ver toda la comunidad.'),
      findsOneWidget,
    );
    expect(avisos.marcadas, 1);

    // Criterio 4: en el foro, con el nombre de quien la publicó y la fecha.
    router.go(ForoScreen.ruta);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ForoScreen.claveSeccion(SeccionForo.rutas)));
    await tester.pumpAndSettle();

    expect(find.byType(TarjetaRuta), findsOneWidget);
    expect(find.text('Cerro Pan de Azucar'), findsOneWidget);
    expect(find.text('Por Ana · Hoy'), findsOneWidget);
    expect(find.text('5.23 km'), findsOneWidget);
  });
}

/// El resumen llega por `extra`, así que no se consulta nada.
class _EntrenamientosFalso implements EntrenamientoRepository {
  @override
  Future<String> crear({required String tipoActividadId}) =>
      throw UnimplementedError();

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) => throw UnimplementedError();

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError();

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) => throw UnimplementedError();
}
