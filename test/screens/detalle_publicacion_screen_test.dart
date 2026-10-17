import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/screens/foro/detalle_publicacion_screen.dart';
import 'package:traza/screens/foro/foro_screen.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/widgets/tarjeta_publicacion.dart';

import '../utiles/foro_repository_falso.dart';

/// El detalle de una publicación con sus comentarios (SCRUM-351) y sus
/// validaciones (SCRUM-352).
void main() {
  final ahora = DateTime(2026, 10, 16, 18);

  late ForoRepositorioFalso repositorio;

  Future<void> abrir(
    WidgetTester tester, {
    List<PublicacionForo>? publicaciones,
    bool soloLectura = false,
    void Function(ForoRepositorioFalso)? preparar,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = ForoRepositorioFalso(
      publicaciones: publicaciones ?? [publicacionDePrueba(id: 'pub-1')],
      ahora: ahora,
    );
    preparar?.call(repositorio);

    final router = GoRouter(
      initialLocation: ForoScreen.ruta,
      routes: [
        GoRoute(
          path: ForoScreen.ruta,
          builder: (_, _) => const ForoScreen(),
          routes: [
            GoRoute(
              path: ':publicacionId',
              builder: (_, state) => DetallePublicacionScreen(
                publicacionId: state.pathParameters['publicacionId']!,
                soloLectura: soloLectura,
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push(DetallePublicacionScreen.rutaDe('pub-1'));
    await tester.pumpAndSettle();
  }

  Future<void> comentar(WidgetTester tester, String texto) async {
    await tester.enterText(
      find.byKey(DetallePublicacionScreen.claveCaja),
      texto,
    );
    await tester.tap(find.byKey(DetallePublicacionScreen.claveEnviar));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra la publicación y sus comentarios con autor y fecha', (
    tester,
  ) async {
    await abrir(
      tester,
      preparar: (r) => r.comentariosDe['pub-1'] = [
        comentarioDePrueba(
          autorNombre: 'Lucía',
          contenido: 'Prueba con drop bajo.',
          fecha: DateTime(2026, 10, 15, 20),
        ),
      ],
    );

    expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
    expect(find.text('COMENTARIOS (1)'), findsOneWidget);
    expect(find.text('Lucía'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    expect(find.text('Prueba con drop bajo.'), findsOneWidget);
  });

  testWidgets('sin comentarios invita a ser el primero', (tester) async {
    await abrir(tester);

    expect(
      find.text('Nadie ha comentado todavía. Sé el primero en opinar.'),
      findsOneWidget,
    );
  });

  testWidgets('al enviar, el comentario aparece bajo la publicación y la '
      'caja se vacía', (tester) async {
    await abrir(tester);

    await comentar(tester, 'Prueba con unos Pegasus.');

    expect(find.text('Prueba con unos Pegasus.'), findsOneWidget);
    expect(find.text('Ana Runner'), findsOneWidget);
    expect(find.text('COMENTARIOS (1)'), findsOneWidget);
    final caja = tester.widget<TextField>(
      find.byKey(DetallePublicacionScreen.claveCaja),
    );
    expect(caja.controller!.text, isEmpty);
  });

  testWidgets('vacío no se envía y dice que no puede estar vacío', (
    tester,
  ) async {
    await abrir(tester);

    await comentar(tester, '   ');

    expect(find.text('El comentario no puede estar vacío.'), findsOneWidget);
    expect(repositorio.comentarioRecibido, isNull);
  });

  testWidgets('una publicación retenida no se puede comentar', (tester) async {
    await abrir(
      tester,
      publicaciones: [
        publicacionDePrueba(id: 'pub-1', estado: EstadoPublicacion.retenida),
      ],
    );

    expect(find.text(DetallePublicacionScreen.noDisponible), findsOneWidget);
    expect(find.byKey(DetallePublicacionScreen.claveCaja), findsNothing);
  });

  testWidgets('una publicación eliminada se informa como no disponible', (
    tester,
  ) async {
    await abrir(tester, publicaciones: []);

    expect(find.text(DetallePublicacionScreen.noDisponible), findsOneWidget);
  });

  testWidgets('si la retiran mientras se escribe, lo informa y quita la caja', (
    tester,
  ) async {
    await abrir(tester);
    repositorio
      ..retener('pub-1')
      ..errorAlComentar = const PublicacionNoDisponibleException();

    await comentar(tester, 'Llego tarde');

    expect(find.text(ComentarioPublicacion.noDisponible), findsOneWidget);
    expect(find.text(DetallePublicacionScreen.noDisponible), findsOneWidget);
    expect(find.byKey(DetallePublicacionScreen.claveCaja), findsNothing);
  });

  testWidgets('el administrador la ve aunque esté retenida, sin caja', (
    tester,
  ) async {
    await abrir(
      tester,
      soloLectura: true,
      publicaciones: [
        publicacionDePrueba(
          id: 'pub-1',
          estado: EstadoPublicacion.retenida,
          motivo: 'spam',
        ),
      ],
    );

    expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
    expect(find.text('Retenida'), findsOneWidget);
    expect(find.text('Motivo: spam'), findsOneWidget);
    expect(find.byKey(DetallePublicacionScreen.claveCaja), findsNothing);
  });

  testWidgets('desde el foro, tocar una publicación abre su detalle', (
    tester,
  ) async {
    await abrir(tester);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(TarjetaPublicacion.claveDe('pub-1')));
    await tester.pumpAndSettle();

    expect(find.byType(DetallePublicacionScreen), findsOneWidget);
  });
}
