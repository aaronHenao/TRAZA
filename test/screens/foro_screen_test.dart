import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/screens/foro/foro_screen.dart';
import 'package:traza/screens/foro/nueva_publicacion_screen.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/foro_repository_falso.dart';

/// El foro (SCRUM-346) y el formulario para publicar en él (SCRUM-344 y
/// SCRUM-345).
void main() {
  // Viernes 16 de octubre de 2026.
  final ahora = DateTime(2026, 10, 16, 18);

  late ForoRepositorioFalso repositorio;

  Future<void> abrirForo(
    WidgetTester tester, {
    List<PublicacionForo> publicaciones = const [],
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = ForoRepositorioFalso(
      publicaciones: publicaciones,
      ahora: ahora,
    );
    final router = GoRouter(
      initialLocation: ForoScreen.ruta,
      routes: [
        GoRoute(
          path: ForoScreen.ruta,
          builder: (_, _) => const ForoScreen(),
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> escribir(
    WidgetTester tester, {
    String titulo = '',
    String contenido = '',
  }) async {
    await tester.enterText(
      find.byKey(NuevaPublicacionScreen.claveTitulo),
      titulo,
    );
    await tester.enterText(
      find.byKey(NuevaPublicacionScreen.claveContenido),
      contenido,
    );
    await tester.pump();
  }

  Future<void> publicar(WidgetTester tester) async {
    await tester.tap(find.byKey(NuevaPublicacionScreen.clavePublicar));
    await tester.pumpAndSettle();
  }

  group('Foro', () {
    testWidgets('muestra cada publicación con su autor y su fecha', (
      tester,
    ) async {
      await abrirForo(
        tester,
        publicaciones: [
          publicacionDePrueba(
            id: 'a',
            titulo: 'Tenis para asfalto',
            autorNombre: 'Carlos',
            fecha: DateTime(2026, 10, 16, 7),
          ),
          publicacionDePrueba(
            id: 'b',
            titulo: 'Ruta en Las Palmas',
            autorNombre: 'Lucía',
            fecha: DateTime(2026, 10, 2, 7),
          ),
        ],
      );

      expect(find.text('Tenis para asfalto'), findsOneWidget);
      expect(find.text('Carlos'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Lucía'), findsOneWidget);
      expect(find.text('2 oct'), findsOneWidget);
    });

    testWidgets('sin publicaciones invita a abrir la conversación', (
      tester,
    ) async {
      await abrirForo(tester);

      expect(find.text('Aún no hay publicaciones'), findsOneWidget);
    });

    testWidgets('si no carga, ofrece reintentar', (tester) async {
      await abrirForo(tester);
      repositorio.error = Exception('sin red');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar el foro'), findsOneWidget);

      repositorio.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Aún no hay publicaciones'), findsOneWidget);
    });
  });

  group('Nueva publicación', () {
    testWidgets('al publicar vuelve al foro y la publicación aparece', (
      tester,
    ) async {
      await abrirForo(tester);
      await tester.tap(find.byKey(ForoScreen.claveNueva));
      await tester.pumpAndSettle();

      await escribir(
        tester,
        titulo: 'Primera media maratón',
        contenido: '¿Cuántas semanas de preparación?',
      );
      await publicar(tester);

      expect(find.byType(NuevaPublicacionScreen), findsNothing);
      expect(find.text('Primera media maratón'), findsOneWidget);
      expect(find.text('Ana Runner'), findsOneWidget);
      expect(find.text(NuevaPublicacionScreen.publicada), findsOneWidget);
    });

    testWidgets('vacía no se publica y señala qué corregir', (tester) async {
      await abrirForo(tester);
      await tester.tap(find.byKey(ForoScreen.claveNueva));
      await tester.pumpAndSettle();

      await publicar(tester);

      expect(find.text('Ponle un título a tu publicación.'), findsOneWidget);
      expect(
        find.text('Escribe el contenido de tu publicación.'),
        findsOneWidget,
      );
      expect(repositorio.recibida, isNull);
      expect(find.byType(NuevaPublicacionScreen), findsOneWidget);
    });

    testWidgets('pasarse del límite no corta el texto: lo señala', (
      tester,
    ) async {
      await abrirForo(tester);
      await tester.tap(find.byKey(ForoScreen.claveNueva));
      await tester.pumpAndSettle();

      final largo = 'a' * (maxCaracteresTituloPublicacion + 5);
      await escribir(tester, titulo: largo, contenido: 'Contenido');

      expect(find.text('125/120'), findsOneWidget);

      await publicar(tester);

      expect(
        find.text('El título no puede superar 120 caracteres.'),
        findsOneWidget,
      );
      expect(repositorio.recibida, isNull);
    });

    testWidgets('el error de un campo se quita al corregirlo', (tester) async {
      await abrirForo(tester);
      await tester.tap(find.byKey(ForoScreen.claveNueva));
      await tester.pumpAndSettle();
      await publicar(tester);

      await tester.enterText(
        find.byKey(NuevaPublicacionScreen.claveTitulo),
        'Ya tiene título',
      );
      await tester.pump();

      expect(find.text('Ponle un título a tu publicación.'), findsNothing);
      expect(
        find.text('Escribe el contenido de tu publicación.'),
        findsOneWidget,
      );
    });

    testWidgets('si queda retenida avisa y no aparece en el foro', (
      tester,
    ) async {
      await abrirForo(tester);
      repositorio.estadoAlCrear = EstadoPublicacion.retenida;
      await tester.tap(find.byKey(ForoScreen.claveNueva));
      await tester.pumpAndSettle();

      await escribir(tester, titulo: 'Oferta', contenido: 'Compra ya');
      await publicar(tester);

      expect(find.text(NuevaPublicacionScreen.retenida), findsOneWidget);
      expect(find.text('Oferta'), findsNothing);
    });

    testWidgets('si falla el guardado conserva lo escrito', (tester) async {
      await abrirForo(tester);
      await tester.tap(find.byKey(ForoScreen.claveNueva));
      await tester.pumpAndSettle();
      repositorio.error = Exception('sin red');

      await escribir(tester, titulo: 'Tenis', contenido: '¿Cuáles?');
      await publicar(tester);

      expect(find.byType(NuevaPublicacionScreen), findsOneWidget);
      expect(find.text('Tenis'), findsOneWidget);
      expect(
        find.text('No se pudo publicar. Inténtalo de nuevo.'),
        findsOneWidget,
      );
    });
  });
}
