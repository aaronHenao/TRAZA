import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/tipo_objetivo.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/screens/home/inicio_screen.dart';
import 'package:traza/screens/home/mapa_progresion_screen.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/historial_service.dart';
import 'package:traza/services/inicio_provider.dart';
import 'package:traza/services/cambios_notificaciones.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/notificaciones_service.dart';
import 'package:traza/services/objetivos_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/screens/notificaciones/notificaciones_screen.dart';
import 'package:traza/widgets/indicadores_semana.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_nivel.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';

import '../utiles/fuente_cambios_notificaciones_falsa.dart';
import '../utiles/notificaciones_falso.dart';
import '../utiles/retos_repository_falso.dart';

/// Historial de mentira: responde lo que la prueba le indique.
class _HistorialFalso implements HistorialRepository {
  _HistorialFalso(this.respuesta);

  Future<List<ResumenEntrenamiento>> Function() respuesta;

  @override
  Future<List<ResumenEntrenamiento>> cargar() => respuesta();
}

/// Los niveles con los que se pinta la tarjeta: con 250 XP va en Bronce y le
/// faltan 250 para Plata.
const _niveles = [
  Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100),
  Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500),
];

/// Objetivos de mentira: solo se le pregunta por la meta de distancia.
class _ObjetivosFalsos implements ObjetivosRepository {
  _ObjetivosFalsos(this.respuesta);

  Future<Map<TipoObjetivo, num>> Function() respuesta;

  @override
  Future<Map<TipoObjetivo, num>> cargar() => respuesta();

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {}
}

/// Retos de mentira: solo se le preguntan los que el corredor activó, para el
/// tercer indicador de la semana (SCRUM-287).
class _RetosFalsos extends RetosRepositorioFalso {
  _RetosFalsos(this.respuesta);

  Future<List<RetoDelUsuario>> Function() respuesta;

  @override
  Future<List<RetoDelUsuario>> misRetos() => respuesta();
}

/// Un reto semanal en juego, con la vigencia abierta sobre la semana que ven
/// las pruebas.
final _retoEnCurso = RetoDelUsuario(
  reto: Reto(
    id: 'r-1',
    nombre: 'Corre 20 km esta semana',
    descripcion: 'Suma 20 km corriendo antes del domingo.',
    periodicidad: PeriodicidadReto.semanal,
    metaKm: 20,
    xpOtorgada: 100,
    vigencia: VigenciaReto(
      inicio: DateTime(2026, 9, 14),
      fin: DateTime(2026, 9, 20),
    ),
    estado: EstadoReto.activo,
    tipoActividad: const TipoActividad(id: 'tipo-correr', nombre: 'Correr'),
  ),
  estado: EstadoRetoUsuario.enProgreso,
  progresoKm: 8,
  fechaActivacion: DateTime(2026, 9, 14, 8),
);

/// Pruebas de la portada: el saludo, los indicadores de la semana, los
/// últimos entrenamientos y las salidas hacia actividad, historial y perfil.
void main() {
  final ahora = DateTime(2026, 9, 16, 10);

  final entrenamientos = [
    ResumenEntrenamiento(
      entrenamientoId: 'e3',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 16, 7),
      duracion: const Duration(minutes: 28, seconds: 14),
      distanciaMetros: 5100,
    ),
    ResumenEntrenamiento(
      entrenamientoId: 'e2',
      nombreActividad: 'Trote',
      fechaFin: DateTime(2026, 9, 15, 7),
      duracion: const Duration(minutes: 20),
      distanciaMetros: 3000,
    ),
    ResumenEntrenamiento(
      entrenamientoId: 'e1',
      nombreActividad: 'Caminar',
      fechaFin: DateTime(2026, 9, 14, 18),
      duracion: const Duration(minutes: 32, seconds: 5),
      distanciaMetros: 2000,
    ),
    // Semana anterior: no entra en el avance ni cabe en los últimos.
    ResumenEntrenamiento(
      entrenamientoId: 'e0',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 11, 18),
      duracion: const Duration(minutes: 15),
      distanciaMetros: 9000,
    ),
  ];

  late NotificacionesFalso avisos;
  late FuenteCambiosNotificacionesFalsa cambiosAvisos;

  Future<GoRouter> abrirPortada(
    WidgetTester tester, {
    Future<List<ResumenEntrenamiento>> Function()? historial,
    Future<Map<TipoObjetivo, num>> Function()? objetivos,
    String? nombre = 'Ana',
    bool esperar = true,
    NivelesFalso? niveles,
    ExperienciaFalsa? experiencia,
    Future<List<RetoDelUsuario>> Function()? retos,
    int sinLeer = 0,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    avisos = NotificacionesFalso(sinLeer: sinLeer);
    cambiosAvisos = FuenteCambiosNotificacionesFalsa();

    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => const InicioScreen()),
        GoRoute(
          path: '/actividad',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Actividad')),
        ),
        GoRoute(
          path: '/perfil',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Perfil')),
        ),
        GoRoute(
          path: MapaProgresionScreen.ruta,
          builder: (_, _) => const Scaffold(body: Text('Pantalla Mapa')),
        ),
        GoRoute(
          path: NotificacionesScreen.ruta,
          builder: (_, _) =>
              const Scaffold(body: Text('Pantalla Notificaciones')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialRepositoryProvider.overrideWithValue(
            _HistorialFalso(historial ?? () async => entrenamientos),
          ),
          objetivosRepositoryProvider.overrideWithValue(
            _ObjetivosFalsos(
              objetivos ?? () async => {TipoObjetivo.distancia: 15},
            ),
          ),
          notificacionesRepositoryProvider.overrideWithValue(avisos),
          fuenteCambiosNotificacionesProvider.overrideWithValue(cambiosAvisos),
          usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
          // El nombre sale de la sesión de Supabase, que en las pruebas no
          // existe.
          nombreUsuarioProvider.overrideWithValue(nombre),
          relojProvider.overrideWithValue(() => ahora),
          // La tarjeta de nivel (SCRUM-286): umbrales y XP acumulada.
          nivelesRepositoryProvider.overrideWithValue(
            niveles ?? NivelesFalso(catalogo: _niveles),
          ),
          experienciaRepositoryProvider.overrideWithValue(
            experiencia ?? ExperienciaFalsa(acumulada: 250),
          ),
          // El tercer indicador de la semana (SCRUM-287).
          retosRepositoryProvider.overrideWithValue(
            _RetosFalsos(retos ?? () async => [_retoEnCurso]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return router;
  }

  group('saludo', () {
    testWidgets('saluda con el nombre de la persona', (tester) async {
      await abrirPortada(tester);

      expect(find.text('Hola, Ana'), findsOneWidget);
      expect(find.text('Vamos por tu meta semanal'), findsOneWidget);
    });

    testWidgets('sin nombre saluda igual, sin dejar el hueco', (tester) async {
      await abrirPortada(tester, nombre: null);

      expect(find.text('Hola'), findsOneWidget);
    });
  });

  group('indicadores de la semana (SCRUM-287)', () {
    String valorDe(WidgetTester tester, Key clave) =>
        tester.widget<Text>(find.byKey(clave)).data!;

    testWidgets('la portada lleva los tres: kilómetros, actividades y retos', (
      tester,
    ) async {
      await abrirPortada(tester);

      expect(find.text('ESTA SEMANA'), findsOneWidget);
      // 5.1 + 3.0 + 2.0 km desde el lunes, contra la meta de 15 del perfil;
      // el entrenamiento de la semana pasada no entra.
      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '10.1 / 15');
      expect(valorDe(tester, IndicadoresSemana.claveActividades), '3');
      expect(valorDe(tester, IndicadoresSemana.claveRetos), '1');
    });

    testWidgets('van entre la tarjeta de nivel y los entrenamientos', (
      tester,
    ) async {
      await abrirPortada(tester);

      final nivel = tester.getTopLeft(find.byKey(TarjetaNivel.clave)).dy;
      final semana = tester.getTopLeft(find.byKey(IndicadoresSemana.clave)).dy;
      final ultimos = tester.getTopLeft(find.text('ÚLTIMOS ENTRENAMIENTOS')).dy;
      expect(semana, greaterThan(nivel));
      expect(semana, lessThan(ultimos));
    });

    testWidgets('sin meta de distancia invita a ponerse una', (tester) async {
      await abrirPortada(tester, objetivos: () async => {});

      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '10.1');
      expect(
        find.text(
          'Ponte una meta de distancia en tu perfil para seguirla desde aquí.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('si los objetivos fallan las cifras se muestran igual', (
      tester,
    ) async {
      await abrirPortada(tester, objetivos: () async => throw Exception('x'));

      expect(valorDe(tester, IndicadoresSemana.claveKilometros), '10.1');
      expect(find.textContaining('No pudimos cargar tu semana'), findsNothing);
    });

    testWidgets('con un solo entrenamiento la etiqueta va en singular', (
      tester,
    ) async {
      await abrirPortada(tester, historial: () async => [entrenamientos.first]);

      expect(valorDe(tester, IndicadoresSemana.claveActividades), '1');
      expect(find.text('actividad'), findsOneWidget);
    });

    testWidgets('mientras carga lo dice, y si falla también', (tester) async {
      final pendiente = Completer<List<ResumenEntrenamiento>>();
      await abrirPortada(
        tester,
        historial: () => pendiente.future,
        esperar: false,
      );

      expect(find.text('Cargando tu semana…'), findsOneWidget);

      pendiente.completeError(Exception('sin red'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No pudimos cargar tu semana'),
        findsOneWidget,
      );
      expect(
        find.text('No pudimos cargar tus entrenamientos.'),
        findsOneWidget,
      );
    });
  });

  group('últimos entrenamientos', () {
    testWidgets('asoma los tres más recientes', (tester) async {
      await abrirPortada(tester);

      expect(find.text('ÚLTIMOS ENTRENAMIENTOS'), findsOneWidget);
      expect(find.text('Correr · hoy'), findsOneWidget);
      expect(find.text('5.10 km · 00:28:14'), findsOneWidget);
      expect(find.text('Trote · ayer'), findsOneWidget);
      expect(find.text('Caminar · 14 sep'), findsOneWidget);
      // El cuarto es de la semana pasada: para verlo está "Ver todos".
      expect(find.text('Correr · 11 sep'), findsNothing);
    });

    testWidgets('sin entrenamientos invita a empezar y no ofrece el '
        'historial', (tester) async {
      await abrirPortada(tester, historial: () async => []);

      expect(
        find.text('Todavía no has entrenado. Toca el botón + para empezar.'),
        findsOneWidget,
      );
      expect(find.text('Ver todos'), findsNothing);
    });

    testWidgets('"Ver todos" abre el historial completo, que vive en el '
        'perfil (SCRUM-285)', (tester) async {
      final router = await abrirPortada(tester);

      await tester.tap(find.text('Ver todos'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Perfil'), findsOneWidget);
      final uri = router.routerDelegate.currentConfiguration.uri;
      expect(uri.path, '/perfil');
      // La pestaña de los entrenamientos, no la del perfil a secas.
      expect(uri.queryParameters['pestana'], 'actividades');
    });
  });

  group('tarjeta de nivel (SCRUM-286)', () {
    testWidgets('la portada abre con el nivel arriba del resumen semanal', (
      tester,
    ) async {
      await abrirPortada(tester);

      expect(find.byKey(TarjetaNivel.clave), findsOneWidget);
      expect(find.text('NIVEL 1'), findsOneWidget);
      expect(find.text('Bronce'), findsOneWidget);
      expect(find.text('250 XP acumulados'), findsOneWidget);
      expect(find.text('Te faltan 250 XP para Plata.'), findsOneWidget);

      // Primero el nivel, después la semana, como en el prototipo.
      expect(
        tester.getTopLeft(find.byKey(TarjetaNivel.clave)).dy,
        lessThan(tester.getTopLeft(find.text('ESTA SEMANA')).dy),
      );
    });
  });

  group('notificaciones (SCRUM-241)', () {
    // Acotado a la campana: desde SCRUM-287 la portada tiene más números a la
    // vista —los indicadores de la semana— y un `find.text('3')` suelto no
    // distingue el globo de una de las cajas.
    Finder enElGlobo(String texto) => find.descendant(
      of: find.byKey(InicioScreen.claveNotificaciones),
      matching: find.text(texto),
    );

    testWidgets('sin avisos sin leer la campana no lleva numero', (
      tester,
    ) async {
      await abrirPortada(tester);

      expect(find.byKey(InicioScreen.claveNotificaciones), findsOneWidget);
      expect(enElGlobo('0'), findsNothing);
    });

    testWidgets('un nombre largo no desborda al lado de la campana', (
      tester,
    ) async {
      await abrirPortada(
        tester,
        nombre: 'Maria Fernanda de los Angeles Restrepo Echavarria',
        sinLeer: 3,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('muestra cuantos avisos lleva sin leer', (tester) async {
      await abrirPortada(tester, sinLeer: 3);

      expect(enElGlobo('3'), findsOneWidget);
    });

    testWidgets('pasado de nueve no dice el numero exacto', (tester) async {
      // El numero exacto no le dice nada a nadie, y el globo no da para mas.
      await abrirPortada(tester, sinLeer: 12);

      expect(enElGlobo('9+'), findsOneWidget);
    });

    testWidgets('un aviso que llega enciende la campana sola', (tester) async {
      // Sin esto habria que volver a la portada o tirar para refrescar para
      // enterarse de que aprobaron la ruta.
      await abrirPortada(tester);
      expect(enElGlobo('1'), findsNothing);
      expect(cambiosAvisos.escuchando, isTrue);

      avisos.llegaron(1);
      cambiosAvisos.emitir('usuario-1');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(enElGlobo('1'), findsOneWidget);
    });

    testWidgets('al salir de la portada deja de escuchar', (tester) async {
      // La conexión solo existe mientras hay algo que la mire.
      await abrirPortada(tester, sinLeer: 1);
      expect(cambiosAvisos.escuchando, isTrue);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(cambiosAvisos.escuchando, isFalse);
    });

    testWidgets('la campana abre la bandeja', (tester) async {
      await abrirPortada(tester, sinLeer: 1);

      await tester.tap(find.byKey(InicioScreen.claveNotificaciones));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Notificaciones'), findsOneWidget);
    });
  });

  group('salidas de la portada', () {
    testWidgets('el "+" lleva a elegir la actividad', (tester) async {
      await abrirPortada(tester);

      await tester.tap(find.byKey(NavegacionPrincipal.claveBoton));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Actividad'), findsOneWidget);
    });

    testWidgets('la barra lleva al perfil', (tester) async {
      await abrirPortada(tester);

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Perfil'), findsOneWidget);
    });

    testWidgets('la tarjeta de nivel abre el mapa de progresión (SCRUM-286)', (
      tester,
    ) async {
      await abrirPortada(tester);

      await tester.tap(find.byKey(TarjetaNivel.clave));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Mapa'), findsOneWidget);
    });
  });
}
