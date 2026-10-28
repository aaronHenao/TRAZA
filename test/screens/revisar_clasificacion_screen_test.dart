import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/detalle_ruta_screen.dart';
import 'package:traza/screens/rutas/revisar_clasificacion_screen.dart';
import 'package:traza/screens/rutas/seccion_rutas.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/services/ubicacion_provider.dart';
import 'package:traza/widgets/mapa_trayecto.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';
import 'package:traza/widgets/tarjeta_ruta_explorar.dart';

import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas de la pantalla donde el Runner Experto revisa la clasificación
/// de una ruta (SCRUM-261, HU-35), y de cómo se llega a ella desde el
/// detalle de la ruta.
void main() {
  late RutasRepositorioFalso repositorio;
  late FuenteUbicacionFalsa fuente;
  late _MockPermisosService permisos;

  /// Una ruta en revisión, con su dificultad propuesta.
  Ruta enRevision({
    Dificultad? dificultad = Dificultad.moderada,
    double? distanciaKm = 7.5,
  }) => rutaDePrueba(
    id: 'ruta-1',
    nombre: 'Subida al Volador',
    autorNombre: 'Luis',
    distanciaKm: distanciaKm,
    dificultad: dificultad,
    trazado: const [
      PuntoRuta(latitud: 6.2650, longitud: -75.5800),
      PuntoRuta(latitud: 6.2680, longitud: -75.5760),
    ],
  );

  setUp(() {
    repositorio = RutasRepositorioFalso(rutas: [enRevision()])
      ..puedeRevisar = true;
    fuente = FuenteUbicacionFalsa()
      ..puntoActual = puntoDePrueba(latitud: 6.2442, longitud: -75.5812);
    permisos = _MockPermisosService();
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
  });

  tearDown(() => fuente.cerrar());

  /// Abre la app en [ubicacion], con la sección de Rutas tal como la
  /// registra la app: debajo quedan Explorar rutas y el detalle.
  Future<void> montar(
    WidgetTester tester, {
    String? ubicacion,
    Size tamano = const Size(390, 844),
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: ubicacion ?? RevisarClasificacionScreen.rutaDe('ruta-1'),
      routes: [seccionRutas],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rutasRepositoryProvider.overrideWithValue(repositorio),
          permisosServiceProvider.overrideWithValue(permisos),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _PermisosGuardadosFalso(),
          ),
          fuenteUbicacionProvider.overrideWithValue(fuente),
          relojProvider.overrideWithValue(() => DateTime(2026, 10, 18, 12)),
          // El mapa no descarga tiles reales.
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Un texto dentro de la tarjeta de un dato.
  Finder enLaTarjeta(Key clave, String texto) =>
      find.descendant(of: find.byKey(clave), matching: find.text(texto));

  group('lo que enseña (criterio 2 de HU-35)', () {
    testWidgets('la ruta: su recorrido, su nombre y de quién es', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text(RevisarClasificacionScreen.titulo), findsOneWidget);
      expect(find.byType(MapaTrayecto), findsOneWidget);
      expect(find.text('Subida al Volador'), findsOneWidget);
      expect(find.textContaining('Por Luis'), findsOneWidget);
    });

    testWidgets('la dificultad propuesta', (tester) async {
      await montar(tester);

      expect(find.text(RevisarClasificacionScreen.rotuloDificultad), findsOne);
      expect(
        enLaTarjeta(RevisarClasificacionScreen.claveDificultad, 'Moderada'),
        findsOneWidget,
      );
      expect(
        enLaTarjeta(
          RevisarClasificacionScreen.claveDificultad,
          RevisarClasificacionScreen.conPropuesta,
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin dificultad todavía, lo dice en vez de inventarse una', (
      tester,
    ) async {
      repositorio = RutasRepositorioFalso(rutas: [enRevision(dificultad: null)])
        ..puedeRevisar = true;
      await montar(tester);

      expect(
        enLaTarjeta(
          RevisarClasificacionScreen.claveDificultad,
          TarjetaRutaExplorar.sinDificultad,
        ),
        findsOneWidget,
      );
      expect(
        enLaTarjeta(
          RevisarClasificacionScreen.claveDificultad,
          RevisarClasificacionScreen.sinPropuesta,
        ),
        findsOneWidget,
      );
    });

    testWidgets('los datos en que se basa: la distancia y el desnivel '
        'acumulado', (tester) async {
      await montar(tester);

      expect(find.text(RevisarClasificacionScreen.rotuloDatos), findsOne);
      expect(
        enLaTarjeta(RevisarClasificacionScreen.claveDistancia, '7.5 km'),
        findsOneWidget,
      );
      expect(
        enLaTarjeta(
          RevisarClasificacionScreen.claveDistancia,
          RevisarClasificacionScreen.distanciaTotal,
        ),
        findsOneWidget,
      );
      // El desnivel no se puede calcular todavía, y se dice por qué.
      expect(
        enLaTarjeta(
          RevisarClasificacionScreen.claveDesnivel,
          TarjetaRutaExplorar.sinDesnivel,
        ),
        findsOneWidget,
      );
      expect(
        enLaTarjeta(
          RevisarClasificacionScreen.claveDesnivel,
          RevisarClasificacionScreen.desnivelNoDisponible,
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin distancia registrada, lo dice sin inventar un número', (
      tester,
    ) async {
      repositorio = RutasRepositorioFalso(
        rutas: [enRevision(distanciaKm: null)],
      )..puedeRevisar = true;
      await montar(tester);

      expect(
        enLaTarjeta(
          RevisarClasificacionScreen.claveDistancia,
          TarjetaRuta.sinDistancia,
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(RevisarClasificacionScreen.claveDistancia),
          matching: find.textContaining(' km'),
        ),
        findsNothing,
      );
    });

    testWidgets('un lector de pantalla lee cada dato junto con lo que es', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);

      final etiqueta = tester
          .getSemantics(find.byKey(RevisarClasificacionScreen.claveDificultad))
          .label;
      expect(etiqueta, contains('Moderada'));
      expect(etiqueta, contains(RevisarClasificacionScreen.conPropuesta));
      semantica.dispose();
    });

    testWidgets('en la pantalla más estrecha con el texto más grande no '
        'desborda, y deslizando se llega a todo', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.6);

      expect(tester.takeException(), isNull);
      // El pie con sus botones queda fijo; lo de arriba se recorre.
      final lista = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      for (final clave in [
        RevisarClasificacionScreen.claveDificultad,
        RevisarClasificacionScreen.claveDesnivel,
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(clave),
          100,
          scrollable: lista,
        );
        expect(find.byKey(clave), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('quién la puede ver (criterio 1 de HU-35)', () {
    testWidgets('le pregunta a la base si se puede revisar esa ruta', (
      tester,
    ) async {
      await montar(tester);

      expect(repositorio.permisosDeRevision, contains('ruta-1'));
    });

    testWidgets('a quien no puede revisar le dice por qué, y no le enseña la '
        'revisión', (tester) async {
      repositorio.puedeRevisar = false;
      await montar(tester);

      expect(find.byKey(RevisarClasificacionScreen.claveSinPermiso), findsOne);
      expect(find.text(RevisarClasificacionScreen.sinPermisoTitulo), findsOne);
      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsNothing,
      );
      expect(find.byType(MapaTrayecto), findsNothing);
    });

    testWidgets('una ruta que ya no existe dice eso, no que falta permiso', (
      tester,
    ) async {
      // Como contesta la base: de una ruta que no existe, que no.
      repositorio = RutasRepositorioFalso()..puedeRevisar = false;
      await montar(tester);

      expect(
        find.byKey(RevisarClasificacionScreen.claveNoDisponible),
        findsOneWidget,
      );
      expect(
        find.byKey(RevisarClasificacionScreen.claveSinPermiso),
        findsNothing,
      );
    });

    testWidgets('si no se puede preguntar, deja reintentar', (tester) async {
      repositorio.errorPermisoRevision = StateError('sin red');
      await montar(tester);

      expect(find.byKey(RevisarClasificacionScreen.claveError), findsOneWidget);

      repositorio.errorPermisoRevision = null;
      await tester.tap(find.byKey(RevisarClasificacionScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsOneWidget,
      );
    });
  });

  group('desde el detalle de la ruta', () {
    testWidgets('quien puede revisar ve el botón, que abre la revisión; '
        '"atrás" vuelve al detalle', (tester) async {
      await montar(tester, ubicacion: DetalleRutaScreen.rutaDe('ruta-1'));

      await tester.tap(find.byKey(RevisarClasificacionScreen.claveAbrir));
      await tester.pumpAndSettle();

      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
      expect(find.byKey(RevisarClasificacionScreen.claveAbrir), findsOne);
    });

    testWidgets('quien no puede revisar no ve el botón', (tester) async {
      repositorio.puedeRevisar = false;
      await montar(tester, ubicacion: DetalleRutaScreen.rutaDe('ruta-1'));

      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
      expect(find.byKey(RevisarClasificacionScreen.claveAbrir), findsNothing);
    });

    testWidgets('si no se puede preguntar, el detalle se ve igual, sin el '
        'botón', (tester) async {
      repositorio.errorPermisoRevision = StateError('sin red');
      await montar(tester, ubicacion: DetalleRutaScreen.rutaDe('ruta-1'));

      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
      expect(find.byKey(RevisarClasificacionScreen.claveAbrir), findsNothing);
    });
  });

  group('confirmar la dificultad propuesta (SCRUM-262, criterio 3 de '
      'HU-35)', () {
    Finder boton() => find.byKey(RevisarClasificacionScreen.claveConfirmar);

    /// Toca "Confirmar", que va al final, después de los datos.
    Future<void> confirmar(WidgetTester tester) async {
      await tester.ensureVisible(boton());
      await tester.pumpAndSettle();
      await tester.tap(boton());
    }

    testWidgets('con una dificultad propuesta, ofrece confirmarla diciendo '
        'cuál', (tester) async {
      await montar(tester);

      expect(find.text('Confirmar como moderada'), findsOneWidget);
    });

    testWidgets('sin dificultad propuesta no hay nada que confirmar: el botón '
        'no aparece', (tester) async {
      repositorio = RutasRepositorioFalso(rutas: [enRevision(dificultad: null)])
        ..puedeRevisar = true;
      await montar(tester);

      expect(find.byKey(RevisarClasificacionScreen.claveDificultad), findsOne);
      expect(boton(), findsNothing);
    });

    testWidgets('confirmar se lo pide a la base, avisa y vuelve al detalle, '
        'que vuelve a pedir la ruta y cuándo se revisó', (tester) async {
      await montar(tester, ubicacion: DetalleRutaScreen.rutaDe('ruta-1'));
      await tester.tap(find.byKey(RevisarClasificacionScreen.claveAbrir));
      await tester.pumpAndSettle();
      final consultas = repositorio.consultasDeRuta;
      final preguntasDeRevision = repositorio.consultasDeRevisadaEn;

      await confirmar(tester);
      await tester.pumpAndSettle();

      expect(repositorio.confirmadas, ['ruta-1']);
      expect(
        find.text(RevisarClasificacionScreen.confirmada(Dificultad.moderada)),
        findsOneWidget,
      );
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsNothing,
      );
      expect(repositorio.consultasDeRuta, greaterThan(consultas));
      expect(
        repositorio.consultasDeRevisadaEn,
        greaterThan(preguntasDeRevision),
      );
    });

    testWidgets('mientras guarda no se puede volver a tocar, y se ve que '
        'guarda', (tester) async {
      repositorio.confirmacionPendiente = Completer<void>();
      await montar(tester);

      await confirmar(tester);
      await tester.pump();

      expect(tester.widget<FilledButton>(boton()).onPressed, isNull);
      expect(
        find.descendant(
          of: boton(),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(boton(), warnIfMissed: false);
      await tester.pump();
      expect(repositorio.confirmadas, ['ruta-1']);

      repositorio.confirmacionPendiente!.complete();
      await tester.pumpAndSettle();

      // Se abrió directo en la revisión: debajo quedó el detalle.
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
    });

    testWidgets('si la base ya no lo deja, lo dice y se queda en la '
        'revisión', (tester) async {
      repositorio.errorConfirmar = const SinPermisoParaRevisarException();
      await montar(tester);

      await confirmar(tester);
      await tester.pumpAndSettle();

      expect(find.text(RevisarClasificacionScreen.yaNoPuedes), findsOneWidget);
      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(boton()).onPressed, isNotNull);
    });

    testWidgets('si falla, lo dice y deja intentarlo otra vez', (tester) async {
      repositorio.errorConfirmar = StateError('sin red');
      await montar(tester);

      await confirmar(tester);
      await tester.pumpAndSettle();
      expect(
        find.text(RevisarClasificacionScreen.noSeConfirmo),
        findsOneWidget,
      );

      repositorio.errorConfirmar = null;
      await confirmar(tester);
      await tester.pumpAndSettle();

      expect(repositorio.confirmadas, ['ruta-1', 'ruta-1']);
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
    });

    testWidgets('en la pantalla más estrecha con el texto más grande, el '
        'botón cabe y se puede tocar', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.6);

      await tester.ensureVisible(boton());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(boton().hitTestable(), findsOneWidget);
    });
  });

  group('corregir la dificultad (SCRUM-263, criterio 4 de HU-35)', () {
    Finder elegirOtra() =>
        find.byKey(RevisarClasificacionScreen.claveElegirOtra);
    Finder guardar() => find.byKey(RevisarClasificacionScreen.claveGuardar);
    Finder opcion(Dificultad dificultad) =>
        find.byKey(RevisarClasificacionScreen.claveOpcion(dificultad));

    Future<void> abrirLaHoja(WidgetTester tester) async {
      await tester.tap(elegirOtra());
      await tester.pumpAndSettle();
    }

    Future<void> elegirYGuardar(
      WidgetTester tester,
      Dificultad dificultad,
    ) async {
      await abrirLaHoja(tester);
      await tester.tap(opcion(dificultad));
      await tester.pumpAndSettle();
      await tester.tap(guardar());
    }

    testWidgets('junto a confirmar, ofrece elegir otra dificultad', (
      tester,
    ) async {
      await montar(tester);

      expect(
        find.descendant(
          of: elegirOtra(),
          matching: find.text(RevisarClasificacionScreen.elegirOtra),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin dificultad propuesta tampoco aparece', (tester) async {
      repositorio = RutasRepositorioFalso(rutas: [enRevision(dificultad: null)])
        ..puedeRevisar = true;
      await montar(tester);

      expect(elegirOtra(), findsNothing);
    });

    testWidgets('la hoja ofrece las otras dos dificultades, no la propuesta, '
        'y no deja guardar sin elegir', (tester) async {
      await montar(tester);

      await abrirLaHoja(tester);

      expect(
        find.text(RevisarClasificacionScreen.queDificultad),
        findsOneWidget,
      );
      expect(opcion(Dificultad.facil), findsOneWidget);
      expect(opcion(Dificultad.dificil), findsOneWidget);
      expect(opcion(Dificultad.moderada), findsNothing);
      expect(tester.widget<FilledButton>(guardar()).onPressed, isNull);
      expect(
        find.descendant(
          of: guardar(),
          matching: find.text(RevisarClasificacionScreen.eligeUna),
        ),
        findsOneWidget,
      );
    });

    testWidgets('al elegir una, el botón dice cómo va a quedar', (
      tester,
    ) async {
      await montar(tester);
      await abrirLaHoja(tester);

      await tester.tap(opcion(Dificultad.dificil));
      await tester.pumpAndSettle();

      expect(find.text('Guardar como difícil'), findsOneWidget);
      expect(tester.widget<FilledButton>(guardar()).onPressed, isNotNull);
    });

    testWidgets('guardar se lo pide a la base con la elegida, avisa y vuelve '
        'al detalle, que vuelve a pedir la ruta y cuándo se revisó', (
      tester,
    ) async {
      await montar(tester, ubicacion: DetalleRutaScreen.rutaDe('ruta-1'));
      await tester.tap(find.byKey(RevisarClasificacionScreen.claveAbrir));
      await tester.pumpAndSettle();
      final consultas = repositorio.consultasDeRuta;
      final preguntasDeRevision = repositorio.consultasDeRevisadaEn;

      await elegirYGuardar(tester, Dificultad.facil);
      await tester.pumpAndSettle();

      expect(repositorio.corregidas, [('ruta-1', Dificultad.facil)]);
      expect(repositorio.confirmadas, isEmpty);
      expect(
        find.text(RevisarClasificacionScreen.corregida(Dificultad.facil)),
        findsOneWidget,
      );
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
      expect(repositorio.consultasDeRuta, greaterThan(consultas));
      expect(
        repositorio.consultasDeRevisadaEn,
        greaterThan(preguntasDeRevision),
      );
    });

    testWidgets('cerrar la hoja sin guardar no cambia nada', (tester) async {
      await montar(tester);
      await abrirLaHoja(tester);
      await tester.tap(opcion(Dificultad.facil));
      await tester.pumpAndSettle();

      // Tocar por encima de la hoja la cierra.
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(guardar(), findsNothing);
      expect(repositorio.corregidas, isEmpty);
      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsOneWidget,
      );
    });

    testWidgets('mientras guarda no se puede tocar ningún botón, y se ve cuál '
        'está guardando', (tester) async {
      repositorio.correccionPendiente = Completer<void>();
      await montar(tester);

      await elegirYGuardar(tester, Dificultad.dificil);
      // Lo que tarda en cerrarse la hoja; el indicador no deja asentar.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.widget<OutlinedButton>(elegirOtra()).onPressed, isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(RevisarClasificacionScreen.claveConfirmar),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.descendant(
          of: elegirOtra(),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      repositorio.correccionPendiente!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
    });

    testWidgets('si la base ya no lo deja, lo dice y se queda en la '
        'revisión', (tester) async {
      repositorio.errorCorregir = const SinPermisoParaRevisarException();
      await montar(tester);

      await elegirYGuardar(tester, Dificultad.facil);
      await tester.pumpAndSettle();

      expect(find.text(RevisarClasificacionScreen.yaNoPuedes), findsOneWidget);
      expect(
        find.byKey(RevisarClasificacionScreen.claveDificultad),
        findsOneWidget,
      );
      expect(tester.widget<OutlinedButton>(elegirOtra()).onPressed, isNotNull);
    });

    testWidgets('si falla, lo dice y deja intentarlo otra vez', (tester) async {
      repositorio.errorCorregir = StateError('sin red');
      await montar(tester);

      await elegirYGuardar(tester, Dificultad.facil);
      await tester.pumpAndSettle();
      expect(
        find.text(RevisarClasificacionScreen.noSeCorrigio),
        findsOneWidget,
      );

      repositorio.errorCorregir = null;
      await elegirYGuardar(tester, Dificultad.facil);
      await tester.pumpAndSettle();

      expect(repositorio.corregidas, [
        ('ruta-1', Dificultad.facil),
        ('ruta-1', Dificultad.facil),
      ]);
      expect(find.byKey(DetalleRutaScreen.claveDistancia), findsOneWidget);
    });

    testWidgets('un lector de pantalla sabe cuál eligió, y que se elige una '
        'sola', (tester) async {
      final semantica = tester.ensureSemantics();
      await montar(tester);
      await abrirLaHoja(tester);

      await tester.tap(opcion(Dificultad.facil));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(opcion(Dificultad.facil)),
        isSemantics(
          label: 'Fácil',
          isButton: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(
        tester.getSemantics(opcion(Dificultad.dificil)),
        isSemantics(label: 'Difícil', isSelected: false),
      );
      semantica.dispose();
    });

    testWidgets('en la pantalla más estrecha con el texto más grande, ni el '
        'pie ni la hoja desbordan', (tester) async {
      await montar(tester, tamano: const Size(320, 568), escalaTexto: 1.6);
      expect(tester.takeException(), isNull);
      expect(elegirOtra().hitTestable(), findsOneWidget);

      await abrirLaHoja(tester);
      await tester.tap(opcion(Dificultad.facil));
      await tester.pumpAndSettle();
      await tester.ensureVisible(guardar());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(guardar().hitTestable(), findsOneWidget);
    });
  });
}
