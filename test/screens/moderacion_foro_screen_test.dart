import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/models/reporte_foro.dart';
import 'package:traza/screens/admin/moderacion_foro_screen.dart';
import 'package:traza/screens/foro/detalle_publicacion_screen.dart';
import 'package:traza/screens/foro/nueva_publicacion_screen.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/widgets/tarjeta_moderacion.dart';
import 'package:traza/widgets/tarjeta_publicacion.dart';

import '../utiles/foro_repository_falso.dart';
import '../utiles/fuente_cambios_foro_falsa.dart';

/// Lo que el administrador ve del foro (SCRUM-323).
///
/// Que un corredor no entre lo cubre `SoloAdministrador`, con sus propias
/// pruebas.
void main() {
  final ahora = DateTime(2026, 10, 16, 18);

  late FuenteCambiosForoFalsa cambios;
  late ForoRepositorioFalso repositorio;
  setUp(() => cambios = FuenteCambiosForoFalsa());

  Future<void> abrir(
    WidgetTester tester,
    List<PublicacionForo> publicaciones, {
    List<ModeracionForo> moderaciones = const [],
    // SCRUM-369: los reportes que ya había y lo que pasó antes de abrir.
    List<ReporteForo> reportes = const [],
    Future<void> Function(ForoRepositorioFalso)? preparar,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = ForoRepositorioFalso(
      publicaciones: publicaciones,
      moderaciones: moderaciones,
      reportes: reportes,
      ahora: ahora,
    );
    await preparar?.call(repositorio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foroRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => ahora),
          usuarioActualProvider.overrideWithValue(() => 'admin-1'),
          fuenteCambiosForoProvider.overrideWithValue(cambios),
        ],
        child: const MaterialApp(home: ModeracionForoScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final publicaciones = [
    publicacionDePrueba(id: 'a', titulo: 'Tenis para asfalto'),
    publicacionDePrueba(
      id: 'b',
      titulo: 'Gana dinero fácil',
      estado: EstadoPublicacion.rechazada,
      motivo: 'Spam',
    ),
  ];

  // SCRUM-322: lo rechazado por la IA, lo que dudó y lo que analiza.
  final moderaciones = [
    moderacionDePrueba(
      id: 'm-rechazo',
      publicacionId: 'b',
      autorId: 'autor-b',
      autorNombre: 'Spammer',
      titulo: 'Gana dinero fácil',
      fechaDecision: DateTime(2026, 10, 16, 14, 5, 9),
    ),
    moderacionDePrueba(
      id: 'm-duda',
      tipo: TipoModeracion.comentario,
      publicacionId: 'a',
      autorId: 'autor-b',
      autorNombre: 'Spammer',
      contenido: 'Esto es una basura',
      estado: EstadoModeracion.pendiente,
      motivo: 'La IA no está segura: lenguaje ofensivo o vulgar',
      categorias: const ['Lenguaje ofensivo o vulgar'],
      responsable: ResponsableModeracion.ia,
    ),
    moderacionDePrueba(
      id: 'm-revision',
      publicacionId: 'a',
      autorId: 'autor-c',
      autorNombre: 'Lucía',
      titulo: 'Rodaje suave',
      contenido: '¿Quién se une el sábado?',
      estado: EstadoModeracion.enRevision,
      motivo: null,
      categorias: const [],
      responsable: null,
    ),
  ];

  Future<void> irA(WidgetTester tester, VistaModeracionForo vista) async {
    await tester.tap(find.byKey(ModeracionForoScreen.claveVista(vista)));
    await tester.pumpAndSettle();
  }

  testWidgets('abre en lo publicado y cuenta cada estado', (tester) async {
    await abrir(tester, publicaciones, moderaciones: moderaciones);

    expect(find.text('Publicadas (1)'), findsOneWidget);
    expect(find.text('Pendientes (1)'), findsOneWidget);
    expect(find.text('En revisión (1)'), findsOneWidget);
    expect(find.text('Rechazadas (1)'), findsOneWidget);
    expect(find.text('Tenis para asfalto'), findsOneWidget);
    expect(find.text('Gana dinero fácil'), findsNothing);
  });

  testWidgets('en rechazadas muestra quién la rechazó, cuándo exactamente y '
      'por qué (SCRUM-322)', (tester) async {
    await abrir(tester, publicaciones, moderaciones: moderaciones);

    await irA(tester, VistaModeracionForo.rechazadas);

    expect(find.text('Gana dinero fácil'), findsOneWidget);
    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.text('Motivo: Spam'), findsOneWidget);
    expect(
      find.text('Rechazada por: Moderación automática (IA)'),
      findsOneWidget,
    );
    expect(find.text('Fecha: 16 oct 2026, 2:05:09 p. m.'), findsOneWidget);
    // Lo rechazado ya no se decide.
    expect(
      find.byKey(TarjetaModeracion.claveAprobar('m-rechazo')),
      findsNothing,
    );
  });

  testWidgets('cuenta las faltas del autor (SCRUM-338)', (tester) async {
    await abrir(
      tester,
      publicaciones,
      moderaciones: [
        ...moderaciones,
        moderacionDePrueba(id: 'm-otra', autorId: 'autor-b'),
      ],
    );

    await irA(tester, VistaModeracionForo.rechazadas);

    expect(find.text(TarjetaModeracion.textoFaltas(2)), findsNWidgets(2));
  });

  testWidgets('en pendientes muestra la duda de la IA y lo aprueba', (
    tester,
  ) async {
    await abrir(tester, publicaciones, moderaciones: moderaciones);
    await irA(tester, VistaModeracionForo.pendientes);

    expect(find.text('Esto es una basura'), findsOneWidget);
    expect(
      find.text(
        'Duda de la IA: La IA no está segura: lenguaje ofensivo o vulgar',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(TarjetaModeracion.claveAprobar('m-duda')));
    await tester.pumpAndSettle();

    expect(repositorio.decisionRecibida, ('m-duda', true, null));
    expect(find.text(ModeracionForoScreen.aprobada), findsOneWidget);
    expect(find.text('Pendientes (0)'), findsOneWidget);
  });

  testWidgets('rechazar exige un motivo, que llega lleno con lo que marcó la '
      'IA', (tester) async {
    await abrir(tester, publicaciones, moderaciones: moderaciones);
    await irA(tester, VistaModeracionForo.pendientes);

    await tester.tap(find.byKey(TarjetaModeracion.claveRechazar('m-duda')));
    await tester.pumpAndSettle();
    expect(find.text('Lenguaje ofensivo o vulgar'), findsWidgets);

    await tester.enterText(find.byKey(ModeracionForoScreen.claveMotivo), ' ');
    await tester.tap(find.byKey(ModeracionForoScreen.claveConfirmarRechazo));
    await tester.pumpAndSettle();
    expect(find.text(DecisionModeracion.sinMotivo), findsOneWidget);
    expect(repositorio.decisionRecibida, isNull);

    await tester.enterText(
      find.byKey(ModeracionForoScreen.claveMotivo),
      'Insulta a otro corredor',
    );
    await tester.tap(find.byKey(ModeracionForoScreen.claveConfirmarRechazo));
    await tester.pumpAndSettle();

    expect(repositorio.decisionRecibida, (
      'm-duda',
      false,
      'Insulta a otro corredor',
    ));
    expect(find.text(ModeracionForoScreen.rechazada), findsOneWidget);
    expect(find.text('Rechazadas (2)'), findsOneWidget);
  });

  testWidgets('lo que la IA no alcanzó a analizar también se puede decidir', (
    tester,
  ) async {
    await abrir(tester, publicaciones, moderaciones: moderaciones);
    await irA(tester, VistaModeracionForo.enRevision);

    expect(find.text('Rodaje suave'), findsOneWidget);
    expect(
      find.byKey(TarjetaModeracion.claveAprobar('m-revision')),
      findsOneWidget,
    );
  });

  testWidgets('el "+" flotante no tapa los botones de la última moderación', (
    tester,
  ) async {
    await abrir(
      tester,
      publicaciones,
      moderaciones: [
        for (var i = 0; i < 6; i++)
          moderacionDePrueba(id: 'm$i', estado: EstadoModeracion.pendiente),
      ],
    );
    expect(
      find.descendant(
        of: find.byKey(ModeracionForoScreen.claveNueva),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );
    await irA(tester, VistaModeracionForo.pendientes);

    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    final aprobar = tester.getRect(
      find.byKey(TarjetaModeracion.claveAprobar('m5')),
    );
    final boton = tester.getRect(find.byKey(ModeracionForoScreen.claveNueva));
    expect(aprobar.bottom, lessThanOrEqualTo(boton.top));
  });

  testWidgets('sin nada pendiente lo dice', (tester) async {
    await abrir(tester, [publicacionDePrueba()]);

    await irA(tester, VistaModeracionForo.pendientes);

    expect(find.text('Nada pendiente'), findsOneWidget);
  });

  testWidgets('el administrador publica desde la moderación y su publicación '
      'dice Administrador', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repositorio = ForoRepositorioFalso(ahora: ahora)..comoAdmin = true;
    final router = GoRouter(
      initialLocation: ModeracionForoScreen.ruta,
      routes: [
        GoRoute(
          path: ModeracionForoScreen.ruta,
          builder: (_, _) => const ModeracionForoScreen(),
          routes: [
            GoRoute(
              path: 'nueva',
              builder: (_, _) => const NuevaPublicacionScreen(),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foroRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => ahora),
          usuarioActualProvider.overrideWithValue(() => 'admin-1'),
          fuenteCambiosForoProvider.overrideWithValue(cambios),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ModeracionForoScreen.claveNueva));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(NuevaPublicacionScreen.claveTitulo),
      'Carrera del domingo',
    );
    await tester.enterText(
      find.byKey(NuevaPublicacionScreen.claveContenido),
      'Salida a las 6 a. m. desde el estadio.',
    );
    await tester.tap(find.byKey(NuevaPublicacionScreen.clavePublicar));
    await tester.pumpAndSettle();

    expect(find.byType(ModeracionForoScreen), findsOneWidget);
    expect(find.text('Carrera del domingo'), findsOneWidget);
    expect(find.text(InsigniaForo.textoAdministrador), findsOneWidget);
  });

  testWidgets('lo nuevo aparece en vivo, sin refrescar (SCRUM-357)', (
    tester,
  ) async {
    await abrir(tester, [publicacionDePrueba(id: 'a', titulo: 'Tenis')]);

    repositorio.publicaciones.insert(
      0,
      publicacionDePrueba(id: 'b', titulo: 'Ruta en Las Palmas'),
    );
    cambios.emitirForo(
      const CambioForo(
        tipo: TipoCambioForo.nuevo,
        tabla: TablaForo.publicaciones,
        id: 'b',
        autorId: 'otro-usuario',
      ),
    );
    await tester.pump(esperaCambiosForo);
    await tester.pumpAndSettle();

    expect(find.text('Ruta en Las Palmas'), findsOneWidget);
    expect(find.text('Publicadas (2)'), findsOneWidget);
  });

  group('reportadas (SCRUM-369)', () {
    // Sobre `publicaciones`: a 'a' la reportaron dos veces; a 'b', una, más
    // tarde (antes de que la rechazaran).
    final reportes = [
      reporteDePrueba(
        id: 'r-b',
        publicacionId: 'b',
        tituloPublicacion: 'Gana dinero fácil',
        autorPublicacion: 'Carlos',
        motivo: MotivoReporte.odio,
        fecha: DateTime(2026, 10, 16, 12),
      ),
      reporteDePrueba(
        id: 'r-a2',
        publicacionId: 'a',
        tituloPublicacion: 'Tenis para asfalto',
        autorPublicacion: 'Carlos',
        motivo: MotivoReporte.spam,
        fecha: DateTime(2026, 10, 16, 11),
      ),
      reporteDePrueba(
        id: 'r-a1',
        publicacionId: 'a',
        tituloPublicacion: 'Tenis para asfalto',
        autorPublicacion: 'Carlos',
        motivo: MotivoReporte.acoso,
        fecha: DateTime(2026, 10, 16, 10),
      ),
    ];

    Finder dentroDe(String publicacionId, Finder buscado) => find.descendant(
      of: find.byKey(ModeracionForoScreen.claveReportada(publicacionId)),
      matching: buscado,
    );

    testWidgets('el chip cuenta las publicaciones reportadas, no los '
        'reportes, y Publicadas no cambia (criterio 1 de SCRUM-369)', (
      tester,
    ) async {
      await abrir(
        tester,
        publicaciones,
        moderaciones: moderaciones,
        reportes: reportes,
      );

      expect(
        find.byKey(
          ModeracionForoScreen.claveVista(VistaModeracionForo.reportadas),
        ),
        findsOneWidget,
      );
      expect(find.text('Reportadas (2)'), findsOneWidget);
      expect(find.text('Publicadas (1)'), findsOneWidget);
      expect(find.text('Pendientes (1)'), findsOneWidget);
      expect(find.text('En revisión (1)'), findsOneWidget);
      expect(find.text('Rechazadas (1)'), findsOneWidget);
      // Sigue abriendo en lo publicado, sin las tarjetas de reportes.
      expect(find.byKey(TarjetaPublicacion.claveDe('a')), findsOneWidget);
      expect(
        find.byKey(ModeracionForoScreen.claveReportada('a')),
        findsNothing,
      );
    });

    testWidgets('muestra cada publicación reportada con cuántos reportes '
        'tiene y sus motivos, la más reciente primero (criterio 1 de '
        'SCRUM-369)', (tester) async {
      await abrir(tester, publicaciones, reportes: reportes);

      await irA(tester, VistaModeracionForo.reportadas);

      expect(dentroDe('a', find.text('Tenis para asfalto')), findsOneWidget);
      expect(dentroDe('a', find.textContaining('Carlos')), findsWidgets);
      expect(
        dentroDe('a', find.textContaining(RegExp(r'\b2 reportes\b'))),
        findsOneWidget,
      );
      expect(
        dentroDe('a', find.textContaining('Acoso o insultos')),
        findsWidgets,
      );
      expect(dentroDe('a', find.textContaining('Spam')), findsWidgets);

      expect(dentroDe('b', find.text('Gana dinero fácil')), findsOneWidget);
      expect(
        dentroDe('b', find.textContaining(RegExp(r'\b1 reporte\b'))),
        findsOneWidget,
      );
      expect(
        dentroDe('b', find.textContaining('Odio o discriminación')),
        findsWidgets,
      );
      expect(
        tester
            .getTopLeft(find.byKey(ModeracionForoScreen.claveReportada('b')))
            .dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(ModeracionForoScreen.claveReportada('a')))
              .dy,
        ),
      );
    });

    testWidgets('la bandeja del administrador recibe el reporte recién hecho '
        '(criterio 1 de SCRUM-369)', (tester) async {
      await abrir(
        tester,
        publicaciones,
        preparar: (r) => r.reportar(
          'a',
          MotivoReporte.violencia,
          detalle: 'Amenaza a otro corredor',
        ),
      );

      expect(find.text('Reportadas (1)'), findsOneWidget);
      await irA(tester, VistaModeracionForo.reportadas);

      expect(dentroDe('a', find.text('Tenis para asfalto')), findsOneWidget);
      expect(
        dentroDe('a', find.textContaining('Violencia o amenazas')),
        findsWidgets,
      );
    });

    testWidgets('al deslizar para recargar aparece lo que se reportó con la '
        'bandeja abierta (criterio 1 de SCRUM-369)', (tester) async {
      await abrir(tester, publicaciones);
      await irA(tester, VistaModeracionForo.reportadas);
      expect(find.text('Nada reportado'), findsOneWidget);

      await repositorio.reportar('a', MotivoReporte.acoso);
      await tester.fling(
        find.byType(ListView).first,
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ModeracionForoScreen.claveReportada('a')),
        findsOneWidget,
      );
      expect(find.text('Reportadas (1)'), findsOneWidget);
    });

    testWidgets('nunca muestra quién reportó (criterio 2 de SCRUM-369)', (
      tester,
    ) async {
      await abrir(
        tester,
        publicaciones,
        preparar: (r) => r.reportar('a', MotivoReporte.acoso),
      );
      expect(repositorio.reportanteDe.values, [ForoRepositorioFalso.usuario]);

      await irA(tester, VistaModeracionForo.reportadas);

      expect(
        find.byKey(ModeracionForoScreen.claveReportada('a')),
        findsOneWidget,
      );
      expect(find.textContaining(ForoRepositorioFalso.usuario), findsNothing);
      expect(find.textContaining('Ana Runner'), findsNothing);
    });

    testWidgets('muestra lo que contó cada corredor al reportar, sin decir '
        'quién (criterio 1 de SCRUM-369)', (tester) async {
      await abrir(
        tester,
        publicaciones,
        reportes: [
          reporteDePrueba(
            id: 'r-1',
            publicacionId: 'a',
            tituloPublicacion: 'Tenis para asfalto',
            motivo: MotivoReporte.otro,
            detalle: 'Publica el teléfono de otra corredora',
          ),
          reporteDePrueba(
            id: 'r-2',
            publicacionId: 'a',
            tituloPublicacion: 'Tenis para asfalto',
            motivo: MotivoReporte.spam,
          ),
        ],
      );

      await irA(tester, VistaModeracionForo.reportadas);

      expect(
        dentroDe(
          'a',
          find.textContaining('Publica el teléfono de otra corredora'),
        ),
        findsOneWidget,
      );
      expect(dentroDe('a', find.textContaining('2 reportes')), findsOneWidget);
    });

    testWidgets('si la bandeja no carga, deja reintentar', (tester) async {
      await abrir(
        tester,
        publicaciones,
        reportes: reportes,
        preparar: (r) async => r.errorAlLeerReportes = Exception('sin red'),
      );
      await irA(tester, VistaModeracionForo.reportadas);

      expect(find.text('No pudimos cargar el foro'), findsOneWidget);
      // Las demás pestañas no se rompen.
      expect(find.text('Publicadas (1)'), findsOneWidget);

      repositorio.errorAlLeerReportes = null;
      final antes = repositorio.consultasReportes;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(repositorio.consultasReportes, greaterThan(antes));
      expect(
        find.byKey(ModeracionForoScreen.claveReportada('a')),
        findsOneWidget,
      );
    });

    testWidgets('sin reportes lo dice', (tester) async {
      await abrir(tester, publicaciones);

      expect(find.text('Reportadas (0)'), findsOneWidget);
      await irA(tester, VistaModeracionForo.reportadas);

      expect(find.text('Nada reportado'), findsOneWidget);
    });

    testWidgets('tocar una reportada abre su detalle de moderación', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repositorio = ForoRepositorioFalso(
        publicaciones: publicaciones,
        reportes: reportes,
        ahora: ahora,
      );
      final router = GoRouter(
        initialLocation: ModeracionForoScreen.ruta,
        routes: [
          GoRoute(
            path: ModeracionForoScreen.ruta,
            builder: (_, _) => const ModeracionForoScreen(),
            routes: [
              GoRoute(
                path: ':publicacionId',
                builder: (_, state) => DetallePublicacionScreen(
                  publicacionId: state.pathParameters['publicacionId']!,
                  vistaModeracion: true,
                ),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            foroRepositoryProvider.overrideWithValue(repositorio),
            relojProvider.overrideWithValue(() => ahora),
            usuarioActualProvider.overrideWithValue(() => 'admin-1'),
            fuenteCambiosForoProvider.overrideWithValue(cambios),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await irA(tester, VistaModeracionForo.reportadas);

      await tester.tap(find.byKey(ModeracionForoScreen.claveReportada('a')));
      await tester.pumpAndSettle();

      final detalle = tester.widget<DetallePublicacionScreen>(
        find.byType(DetallePublicacionScreen),
      );
      expect(detalle.publicacionId, 'a');
      expect(detalle.vistaModeracion, isTrue);
      expect(find.text('Tenis para asfalto'), findsOneWidget);
    });
  });

  group('eliminar una publicación (SCRUM-242)', () {
    /// Lo retirado sale de las listas, así que el resultado se comprueba en
    /// el repositorio.
    PublicacionForo laPublicacion(String id) =>
        repositorio.publicaciones.firstWhere((p) => p.id == id);

    Future<void> abrirComoAdmin(
      WidgetTester tester, {
      List<ReporteForo> reportes = const [],
    }) => abrir(
      tester,
      publicaciones,
      reportes: reportes,
      preparar: (r) async => r.comoAdmin = true,
    );

    Future<void> pedirRetiro(WidgetTester tester, Key boton) async {
      await tester.tap(find.byKey(boton));
      await tester.pumpAndSettle();
    }

    Future<void> escribirMotivo(WidgetTester tester, String motivo) async {
      await tester.enterText(
        find.byKey(ModeracionForoScreen.claveMotivoRetiro),
        motivo,
      );
      await tester.pump();
    }

    Future<void> confirmar(WidgetTester tester) async {
      await tester.tap(find.byKey(ModeracionForoScreen.claveConfirmarRetiro));
      await tester.pumpAndSettle();
    }

    testWidgets('se ofrece en publicadas y en reportadas (criterio 1)', (
      tester,
    ) async {
      await abrirComoAdmin(
        tester,
        reportes: [reporteDePrueba(publicacionId: 'a')],
      );

      expect(
        find.byKey(TarjetaPublicacion.claveEliminarDe('a')),
        findsOneWidget,
      );

      await irA(tester, VistaModeracionForo.reportadas);
      expect(
        find.byKey(ModeracionForoScreen.claveEliminarReportada('a')),
        findsOneWidget,
      );
    });

    testWidgets('pide confirmación diciendo que avisará al autor y que '
        'quedará registrado', (tester) async {
      await abrirComoAdmin(tester);

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));

      expect(find.text('Eliminar publicación'), findsOneWidget);
      expect(find.textContaining('Tenis para asfalto'), findsWidgets);
      expect(find.textContaining('Avisaremos a su autor'), findsOneWidget);
      expect(find.textContaining('bitácora de moderación'), findsOneWidget);
    });

    testWidgets('cancelar no retira nada', (tester) async {
      await abrirComoAdmin(tester);

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(laPublicacion('a').estado, EstadoPublicacion.publicada);
      expect(repositorio.retiros, isEmpty);
      expect(find.byKey(TarjetaPublicacion.claveDe('a')), findsOneWidget);
    });

    testWidgets('sin motivo no deja confirmar y lo dice en el campo', (
      tester,
    ) async {
      await abrirComoAdmin(tester);

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));
      await confirmar(tester);

      // El diálogo sigue abierto y no se tocó la base.
      expect(find.text('Eliminar publicación'), findsOneWidget);
      expect(find.text(RetiroPublicacion.sinMotivo), findsOneWidget);
      expect(repositorio.retiros, isEmpty);
      expect(laPublicacion('a').estado, EstadoPublicacion.publicada);
    });

    testWidgets('el error del motivo se quita al escribirlo', (tester) async {
      await abrirComoAdmin(tester);

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));
      await confirmar(tester);
      expect(find.text(RetiroPublicacion.sinMotivo), findsOneWidget);

      await escribirMotivo(tester, 'Lenguaje ofensivo');

      expect(find.text(RetiroPublicacion.sinMotivo), findsNothing);
    });

    testWidgets('al confirmar con motivo la retira, lo dice y la saca de la '
        'lista (criterio 1)', (tester) async {
      await abrirComoAdmin(tester);

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));
      await escribirMotivo(tester, 'Lenguaje ofensivo');
      await confirmar(tester);

      expect(laPublicacion('a').estado, EstadoPublicacion.eliminada);
      expect(laPublicacion('a').motivoModeracion, 'Lenguaje ofensivo');
      expect(find.text(RetiroPublicacion.retirada), findsOneWidget);
      // La lista se rehace sola: no hace falta refrescar.
      expect(find.byKey(TarjetaPublicacion.claveDe('a')), findsNothing);
      expect(find.text('Publicadas (0)'), findsOneWidget);
    });

    testWidgets('retirada desde reportadas, su reporte sale de la bandeja', (
      tester,
    ) async {
      await abrirComoAdmin(
        tester,
        reportes: [reporteDePrueba(publicacionId: 'a')],
      );
      await irA(tester, VistaModeracionForo.reportadas);
      expect(find.text('Reportadas (1)'), findsOneWidget);

      await pedirRetiro(
        tester,
        ModeracionForoScreen.claveEliminarReportada('a'),
      );
      await escribirMotivo(tester, 'Spam');
      await confirmar(tester);

      expect(laPublicacion('a').estado, EstadoPublicacion.eliminada);
      expect(
        find.byKey(ModeracionForoScreen.claveReportada('a')),
        findsNothing,
      );
      expect(find.text('Reportadas (0)'), findsOneWidget);
    });

    testWidgets('deja el asiento y avisa al autor (criterios 2 y 3)', (
      tester,
    ) async {
      await abrirComoAdmin(tester);

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));
      await escribirMotivo(tester, 'Lenguaje ofensivo');
      await confirmar(tester);

      expect(repositorio.retiros, [('a', 'Lenguaje ofensivo')]);
      expect(repositorio.avisosDeRetiro, [('autor-a', 'Lenguaje ofensivo')]);
    });

    testWidgets('si otro administrador se adelantó, lo dice', (tester) async {
      await abrirComoAdmin(tester);
      // Otro la retira mientras esta lista está en pantalla: la tarjeta
      // sigue ahí porque nada la invalidó.
      await repositorio.retirar('a', 'Spam');

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));
      await escribirMotivo(tester, 'Otra vez');
      await confirmar(tester);

      expect(find.text(RetiroPublicacion.yaRetirada), findsOneWidget);
      expect(repositorio.retiros, hasLength(1));
    });

    testWidgets('un fallo de red lo avisa y no saca la publicación', (
      tester,
    ) async {
      await abrirComoAdmin(tester);
      repositorio.errorAlRetirar = Exception('sin red');

      await pedirRetiro(tester, TarjetaPublicacion.claveEliminarDe('a'));
      await escribirMotivo(tester, 'Spam');
      await confirmar(tester);

      expect(find.text(RetiroPublicacion.noSePudo), findsOneWidget);
      expect(laPublicacion('a').estado, EstadoPublicacion.publicada);
      expect(find.byKey(TarjetaPublicacion.claveDe('a')), findsOneWidget);
    });
  });
}
