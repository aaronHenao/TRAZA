import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/screens/admin/moderacion_foro_screen.dart';
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
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = ForoRepositorioFalso(
      publicaciones: publicaciones,
      moderaciones: moderaciones,
      ahora: ahora,
    );
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
}
