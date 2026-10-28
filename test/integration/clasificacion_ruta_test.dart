// Pruebas de integración de la clasificación de una ruta por un Runner
// Experto (SCRUM-363, subtask SCRUM-368): el autor la manda desde el resumen
// de su entrenamiento, el administrador la aprueba (SCRUM-321), un Runner
// Experto la encuentra en su perfil y le asigna la dificultad, y el autor la
// confirma y queda publicada con ella. También el camino de la ruta sin
// distancia, que no se puede clasificar.
//
// Cada sesión es otro teléfono: un `ProviderScope` y un router nuevos, con
// las pantallas de verdad. Lo único compartido es el repositorio de rutas
// en memoria, que hace de base y repite las reglas de `preparar_ruta`,
// `decidir_revision_ruta`, `clasificar_ruta` y `confirmar_publicacion_ruta`
// (0045 y 0048).
//
// Lo que estas pruebas NO prueban: que la base decida el estado al crear,
// que solo un experto pueda clasificar ni el aviso `ruta_clasificada`. Eso
// lo hace Postgres y no se puede ejecutar desde aquí; su verificación está
// escrita al final de `0048_flujo_unico_de_revision.sql`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/tipo_objetivo.dart';
import 'package:traza/screens/onboarding/perfil_screen.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/publicar_ruta_screen.dart';
import 'package:traza/screens/rutas/rutas_por_clasificar_screen.dart';
import 'package:traza/screens/summary/resumen_screen.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/insignias_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/objetivos_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/roles_service.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/solo_experto.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/insignias_falsas.dart';
import '../utiles/niveles_falso.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/roles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

void main() {
  final ahora = DateTime(2026, 10, 17, 12);

  final recorrido = [
    for (var i = 0; i < 40; i++)
      PuntoGps(
        latitud: 6.2442 + i / 10000,
        longitud: -75.5812,
        capturadoEn: DateTime(2026, 10, 17, 7, i),
      ),
  ];

  ResumenEntrenamiento entrenamiento({double? distanciaMetros = 5230.5}) =>
      ResumenEntrenamiento(
        entrenamientoId: 'e-123',
        nombreActividad: 'Trote',
        fechaFin: DateTime(2026, 10, 17, 8),
        duracion: const Duration(minutes: 32),
        distanciaMetros: distanciaMetros,
        puntos: recorrido,
      );

  late RutasRepositorioFalso base;

  setUp(() => base = RutasRepositorioFalso());

  /// Abre la app con la sesión de [usuario] en [en]. Lo de la sesión
  /// anterior se descarta entero: es otro teléfono.
  Future<void> abrirApp(
    WidgetTester tester, {
    required String usuario,
    required String en,
    bool experto = false,
    Object? extra,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    base.usuario = usuario;

    final router = GoRouter(
      initialLocation: en,
      initialExtra: extra,
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
          path: PerfilScreen.ruta,
          builder: (_, _) => const PerfilScreen(),
        ),
        // Como la registrará `main.dart`: tras `SoloExperto`.
        GoRoute(
          path: RutasPorClasificarScreen.ruta,
          builder: (_, _) =>
              const SoloExperto(hijo: RutasPorClasificarScreen()),
        ),
        // Como en `seccionRutas`: publicar antes que el detalle, para que
        // 'publicar' no se tome por el id de una ruta.
        GoRoute(
          path: PublicarRutaScreen.ruta,
          builder: (_, estado) => PublicarRutaScreen(
            resumen: estado.extra as ResumenEntrenamiento?,
          ),
        ),
        GoRoute(
          path: DetalleRutaScreen.ruta,
          builder: (_, estado) => DetalleRutaScreen(
            rutaId: estado.pathParameters['rutaId']!,
            vistaPrevia: estado.extra as Ruta?,
          ),
        ),
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Portada')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relojProvider.overrideWithValue(() => ahora),
          usuarioActualProvider.overrideWithValue(() => base.usuario),
          rutasRepositoryProvider.overrideWithValue(base),
          rolesRepositoryProvider.overrideWithValue(
            experto ? RolesFalso.experto() : RolesFalso(),
          ),
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
          objetivosRepositoryProvider.overrideWithValue(_ObjetivosFalso()),
          insigniasRepositoryProvider.overrideWithValue(InsigniasFalsas()),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Desde el resumen recién abierto, publica su recorrido con un nombre.
  Future<void> publicarDesdeElResumen(WidgetTester tester) async {
    await _tocar(tester, find.byKey(ResumenScreen.clavePublicarRuta));
    await tester.enterText(
      find.byKey(PublicarRutaScreen.claveNombre),
      'Vuelta al Parque Norte',
    );
    await _tocar(tester, find.byKey(PublicarRutaScreen.clavePublicar));
  }

  /// Desde el resumen, vuelve a "Publicar como ruta" y de ahí a su ruta.
  Future<void> abrirMiRutaDesdeElResumen(
    WidgetTester tester, {
    required String estado,
  }) async {
    await _tocar(tester, find.byKey(ResumenScreen.clavePublicarRuta));
    expect(_en(PublicarRutaScreen.claveYaPublicada, estado), findsOneWidget);
    await _tocar(tester, find.byKey(PublicarRutaScreen.claveVerRuta));
    expect(find.byType(DetalleRutaScreen), findsOneWidget);
  }

  /// Desde el perfil del experto, abre su bandeja.
  Future<void> abrirLaBandejaDesdeElPerfil(WidgetTester tester) async {
    final tarjeta = find.byKey(PerfilScreen.claveRutasPorClasificar);
    await tester.scrollUntilVisible(
      tarjeta,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await _tocar(tester, tarjeta);
    expect(find.byType(RutasPorClasificarScreen), findsOneWidget);
  }

  testWidgets('con la distancia: la aprueba el administrador, va a un Runner '
      'Experto, que le asigna la dificultad, y el autor la publica '
      'mostrándola (SCRUM-321, criterios 1 y 2 de SCRUM-363)', (tester) async {
    // --- El autor la manda a clasificar ---
    await abrirApp(
      tester,
      usuario: 'autor-1',
      en: '/resumen/e-123',
      extra: entrenamiento(),
    );
    await publicarDesdeElResumen(tester);

    // Criterio 1: se le dice que quedó pendiente de revisión...
    expect(find.text(PublicacionRuta.enRevision), findsOneWidget);
    expect(find.textContaining('pendiente de revisión'), findsOneWidget);
    expect(find.byType(ResumenScreen), findsOneWidget);
    expect(base.rutas.single.estado, EstadoRuta.enRevision);
    await _esperarQueSeVayaElAviso(tester);

    // ...y es lo que ve cuando vuelve a mirarla, sin poder publicarla aún.
    await abrirMiRutaDesdeElResumen(
      tester,
      estado: 'Pendiente de revisión del administrador',
    );
    expect(
      _en(
        DetalleRutaScreen.claveEstado,
        'Pendiente de revisión del administrador',
      ),
      findsOneWidget,
    );
    expect(
      _en(DetalleRutaScreen.claveDificultad, 'Sin clasificar'),
      findsOneWidget,
    );
    expect(find.byKey(DetalleRutaScreen.clavePublicar), findsNothing);

    // --- Mientras el administrador no la apruebe, al experto no le llega ---
    await abrirApp(
      tester,
      usuario: 'experto-1',
      experto: true,
      en: PerfilScreen.ruta,
    );
    await abrirLaBandejaDesdeElPerfil(tester);
    expect(find.text('No hay rutas por clasificar'), findsOneWidget);

    // --- El administrador la aprueba (SCRUM-321) ---
    // Su pantalla no está en este repo: el doble hace lo que
    // `decidir_revision_ruta` al aprobar.
    base.aprobarComoAdministrador(base.rutas.single.id);

    // --- Un Runner Experto la encuentra en su perfil y la clasifica ---
    await abrirApp(
      tester,
      usuario: 'experto-1',
      experto: true,
      en: PerfilScreen.ruta,
    );
    await abrirLaBandejaDesdeElPerfil(tester);
    await _tocar(tester, find.text('Vuelta al Parque Norte'));

    expect(find.byType(DetalleRutaScreen), findsOneWidget);
    expect(find.byKey(DetalleRutaScreen.claveEstado), findsNothing);
    await _tocar(
      tester,
      find.byKey(DetalleRutaScreen.claveOpcionDificultad(Dificultad.moderada)),
    );
    await _tocar(tester, find.byKey(DetalleRutaScreen.claveAsignar));

    // Vuelve a su bandeja, donde la ruta ya no está.
    expect(find.text(ClasificacionRuta.clasificada), findsOneWidget);
    expect(find.byType(RutasPorClasificarScreen), findsOneWidget);
    expect(find.text('Vuelta al Parque Norte'), findsNothing);
    expect(find.text('No hay rutas por clasificar'), findsOneWidget);
    expect(base.rutas.single.estado, EstadoRuta.clasificada);
    expect(base.rutas.single.dificultad, Dificultad.moderada);

    // --- El autor confirma y queda publicada con su dificultad ---
    await abrirApp(
      tester,
      usuario: 'autor-1',
      en: '/resumen/e-123',
      extra: entrenamiento(),
    );
    await abrirMiRutaDesdeElResumen(tester, estado: 'Lista para publicar');
    expect(
      _en(DetalleRutaScreen.claveEstado, 'Lista para publicar'),
      findsOneWidget,
    );
    expect(_en(DetalleRutaScreen.claveDificultad, 'Moderada'), findsOneWidget);

    await _tocar(tester, find.byKey(DetalleRutaScreen.clavePublicar));

    // Criterio 2: publicada, con su nivel y quién lo asignó.
    expect(find.text(ConfirmacionPublicacionRuta.publicada), findsOneWidget);
    expect(base.rutas.single.estado, EstadoRuta.publicada);
    expect(base.rutas.single.dificultad, Dificultad.moderada);
    expect(find.byKey(DetalleRutaScreen.claveEstado), findsNothing);
    expect(find.byKey(DetalleRutaScreen.clavePublicar), findsNothing);
    expect(_en(DetalleRutaScreen.claveDificultad, 'Moderada'), findsOneWidget);
    expect(
      _en(DetalleRutaScreen.claveDificultad, 'Asignada por un Runner Experto'),
      findsOneWidget,
    );
  });

  testWidgets('sin la distancia: informa que no puede clasificarse, la '
      'registra con la dificultad pendiente y no le llega al experto '
      '(criterio 3 de SCRUM-363)', (tester) async {
    // La base no le encuentra distancia al entrenamiento.
    base.distanciaNueva = null;

    // --- El autor la manda ---
    await abrirApp(
      tester,
      usuario: 'autor-1',
      en: '/resumen/e-123',
      extra: entrenamiento(distanciaMetros: null),
    );
    await publicarDesdeElResumen(tester);

    expect(find.text(PublicacionRuta.sinDatosParaClasificar), findsOneWidget);
    expect(find.byType(ResumenScreen), findsOneWidget);
    expect(base.rutas.single.estado, EstadoRuta.datosIncompletos);
    expect(base.rutas.single.dificultad, isNull);
    await _esperarQueSeVayaElAviso(tester);

    // Es lo que ve cuando vuelve a mirarla.
    await abrirMiRutaDesdeElResumen(tester, estado: 'Dificultad pendiente');
    expect(
      _en(DetalleRutaScreen.claveEstado, 'Dificultad pendiente'),
      findsOneWidget,
    );
    expect(
      _en(
        DetalleRutaScreen.claveEstado,
        'No se puede clasificar: falta la distancia de la ruta.',
      ),
      findsOneWidget,
    );
    expect(
      _en(DetalleRutaScreen.claveDificultad, 'Sin clasificar'),
      findsOneWidget,
    );
    expect(find.byKey(DetalleRutaScreen.clavePublicar), findsNothing);

    // --- Al Runner Experto no le llega ---
    await abrirApp(
      tester,
      usuario: 'experto-1',
      experto: true,
      en: PerfilScreen.ruta,
    );
    await abrirLaBandejaDesdeElPerfil(tester);

    expect(find.text('No hay rutas por clasificar'), findsOneWidget);
    expect(find.text('Vuelta al Parque Norte'), findsNothing);
  });
}

/// [texto] dentro del widget con [clave].
Finder _en(Key clave, String texto) =>
    find.descendant(of: find.byKey(clave), matching: find.text(texto));

/// Lo trae a la vista antes de tocarlo.
Future<void> _tocar(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.pumpAndSettle();
  await tester.tap(objetivo);
  await tester.pumpAndSettle();
}

/// Deja pasar el aviso del pie, para que no tape lo que se toca después.
Future<void> _esperarQueSeVayaElAviso(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
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

/// El perfil del experto pide sus objetivos al abrir; no tiene ninguno.
class _ObjetivosFalso implements ObjetivosRepository {
  @override
  Future<Map<TipoObjetivo, num>> cargar() async => const {};

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {}
}
