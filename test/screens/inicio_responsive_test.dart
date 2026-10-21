import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/tipo_objetivo.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/screens/home/inicio_screen.dart';
import 'package:traza/services/cambios_notificaciones.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/historial_service.dart';
import 'package:traza/services/inicio_provider.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/notificaciones_service.dart';
import 'package:traza/services/objetivos_service.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/carrusel_rutas_cercanas.dart';
import 'package:traza/widgets/indicadores_semana.dart';
import 'package:traza/widgets/navegacion_principal.dart';
import 'package:traza/widgets/tarjeta_nivel.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';
import '../utiles/fuente_cambios_notificaciones_falsa.dart';
import '../utiles/notificaciones_falso.dart';
import '../utiles/retos_repository_falso.dart';
import '../utiles/rutas_repository_falso.dart';

class _MockPermisosService extends Mock implements PermisosService {}

class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

class _HistorialFalso implements HistorialRepository {
  _HistorialFalso(this.entrenamientos);

  final List<ResumenEntrenamiento> entrenamientos;

  @override
  Future<List<ResumenEntrenamiento>> cargar() async => entrenamientos;
}

class _ObjetivosFalsos implements ObjetivosRepository {
  @override
  Future<Map<TipoObjetivo, num>> cargar() async => {TipoObjetivo.distancia: 15};

  @override
  Future<void> guardar(Map<TipoObjetivo, num> objetivos) async {}
}

class _RetosFalsos extends RetosRepositorioFalso {
  _RetosFalsos(this.mios);

  final List<RetoDelUsuario> mios;

  @override
  Future<List<RetoDelUsuario>> misRetos() async => mios;
}

/// La portada en los anchos de pantalla que se van a usar de verdad, y con el
/// texto del sistema agrandado (SCRUM-291).
///
/// Un desbordamiento de layout hace fallar la prueba por sí solo, así que
/// montar la portada en cada tamaño ya es la comprobación. Lo demás son los
/// bloques que no se pueden perder por estrecha que sea la pantalla.
void main() {
  // Miércoles 16 de septiembre.
  final ahora = DateTime(2026, 9, 16, 10);

  // Anchos reales: el más estrecho que se sigue vendiendo, el Android común,
  // un iPhone actual, un teléfono grande y una tableta pequeña.
  const tamanos = {
    'estrecho': Size(320, 568),
    'común': Size(360, 640),
    'normal': Size(390, 844),
    'grande': Size(430, 932),
    'tableta': Size(768, 1024),
  };

  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');

  final entrenamientos = [
    ResumenEntrenamiento(
      entrenamientoId: 'e2',
      nombreActividad: 'Correr',
      fechaFin: DateTime(2026, 9, 16, 7),
      duracion: const Duration(minutes: 28, seconds: 14),
      distanciaMetros: 5100,
    ),
    ResumenEntrenamiento(
      entrenamientoId: 'e1',
      nombreActividad: 'Caminar',
      fechaFin: DateTime(2026, 9, 15, 18),
      duracion: const Duration(minutes: 32, seconds: 5),
      distanciaMetros: 3000,
    ),
  ];

  final reto = RetoDelUsuario(
    reto: Reto(
      id: 'r-1',
      // Largo a propósito: es lo que aprieta la tarjeta en 320 px.
      nombre: 'Corre 20 kilómetros esta semana sin parar en el camino',
      descripcion: 'Suma 20 km corriendo antes del domingo.',
      periodicidad: PeriodicidadReto.semanal,
      metaKm: 20,
      xpOtorgada: 1000,
      vigencia: VigenciaReto(
        inicio: DateTime(2026, 9, 14),
        fin: DateTime(2026, 9, 20),
      ),
      estado: EstadoReto.activo,
      tipoActividad: correr,
    ),
    estado: EstadoRetoUsuario.enProgreso,
    progresoKm: 8,
    fechaActivacion: DateTime(2026, 9, 14, 8),
  );

  final rutas = [
    rutaDePrueba(
      id: 'r-1',
      nombre: 'Vuelta completa al estadio Atanasio Girardot',
      estado: EstadoRuta.publicada,
      distanciaKm: 5.23,
      fechaPublicacion: DateTime(2026, 9, 15, 9),
    ),
    rutaDePrueba(
      id: 'r-2',
      nombre: 'Subida al cerro Nutibara',
      estado: EstadoRuta.publicada,
      distanciaKm: 12.4,
      fechaPublicacion: DateTime(2026, 9, 14, 9),
    ),
  ];

  const niveles = [
    Nivel(id: 'n-1', nombre: 'Corredor de Bronce', umbralExperiencia: 100),
    Nivel(id: 'n-2', nombre: 'Corredor de Plata', umbralExperiencia: 500),
  ];

  Future<void> montar(
    WidgetTester tester,
    Size tamano, {
    double escalaTexto = 1,
    EstadoPermiso ubicacion = EstadoPermiso.concedido,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final permisos = _MockPermisosService();
    when(() => permisos.estadoUbicacion()).thenAnswer((_) async => ubicacion);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});

    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(path: '/inicio', builder: (_, _) => const InicioScreen()),
        for (final seccion in SeccionPrincipal.values)
          if (seccion != SeccionPrincipal.inicio)
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
          historialRepositoryProvider.overrideWithValue(
            _HistorialFalso(entrenamientos),
          ),
          objetivosRepositoryProvider.overrideWithValue(_ObjetivosFalsos()),
          nivelesRepositoryProvider.overrideWithValue(
            NivelesFalso(catalogo: niveles),
          ),
          experienciaRepositoryProvider.overrideWithValue(
            ExperienciaFalsa(acumulada: 250),
          ),
          retosRepositoryProvider.overrideWithValue(_RetosFalsos([reto])),
          rutasRepositoryProvider.overrideWithValue(
            RutasRepositorioFalso(rutas: rutas),
          ),
          notificacionesRepositoryProvider.overrideWithValue(
            NotificacionesFalso(sinLeer: 12),
          ),
          fuenteCambiosNotificacionesProvider.overrideWithValue(
            FuenteCambiosNotificacionesFalsa(),
          ),
          usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
          permisosServiceProvider.overrideWithValue(permisos),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _PermisosGuardadosFalso(),
          ),
          nombreUsuarioProvider.overrideWithValue('Ana'),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('la portada entra en cualquier pantalla', () {
    for (final tamano in tamanos.entries) {
      testWidgets('ancho ${tamano.key}', (tester) async {
        await montar(tester, tamano.value);

        // Lo de arriba se ve en cualquier tamaño; lo de abajo depende del
        // alto, y lo que se comprueba es que se arma sin desbordar.
        expect(find.text('Hola, Ana'), findsOneWidget);
        expect(find.byKey(InicioScreen.claveNotificaciones), findsOneWidget);
        expect(find.byKey(TarjetaNivel.clave), findsOneWidget);
        expect(find.byKey(IndicadoresSemana.clave), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('ancho ${tamano.key} con el texto del sistema grande', (
        tester,
      ) async {
        await montar(tester, tamano.value, escalaTexto: 1.3);

        expect(find.text('Hola, Ana'), findsOneWidget);
        expect(find.byKey(TarjetaNivel.clave), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('en la pantalla más estrecha', () {
    testWidgets('las tres cifras de la semana siguen enteras', (tester) async {
      await montar(tester, tamanos['estrecho']!);

      expect(
        tester.widget<Text>(find.byKey(IndicadoresSemana.claveKilometros)).data,
        '8.1 / 15',
      );
      expect(
        tester.widget<Text>(find.byKey(IndicadoresSemana.claveRetos)).data,
        '1',
      );
    });

    testWidgets('el nombre largo del nivel no desborda su tarjeta', (
      tester,
    ) async {
      await montar(tester, tamanos['estrecho']!);

      expect(find.text('Corredor de Bronce'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la barra y el "+" siguen accesibles', (tester) async {
      await montar(tester, tamanos['estrecho']!);

      expect(find.byKey(NavegacionPrincipal.claveBoton), findsOneWidget);
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();

      expect(find.text('En Perfil'), findsOneWidget);
    });

    testWidgets('con el texto grande, el carrusel de rutas se recorre igual', (
      tester,
    ) async {
      await montar(tester, tamanos['estrecho']!, escalaTexto: 1.3);

      await tester.scrollUntilVisible(
        find.byKey(CarruselRutasCercanas.clave),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Subida al cerro Nutibara'),
        200,
        scrollable: find.descendant(
          of: find.byKey(CarruselRutasCercanas.clave),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Subida al cerro Nutibara'), findsOneWidget);
    });
  });

  testWidgets('en una tableta la portada no se estira a lo ancho sin medida', (
    tester,
  ) async {
    await montar(tester, tamanos['tableta']!);

    // Las tarjetas ocupan el ancho que les deja la portada; lo que se
    // comprueba es que no se rompan ni dejen el contenido pegado al borde.
    final tarjeta = tester.getRect(find.byKey(TarjetaNivel.clave));
    expect(tarjeta.left, greaterThanOrEqualTo(16));
    expect(tarjeta.right, lessThanOrEqualTo(768 - 16));
  });
}
