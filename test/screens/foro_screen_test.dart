import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/screens/foro/foro_screen.dart';
import 'package:traza/screens/foro/mis_rechazados_screen.dart';
import 'package:traza/screens/foro/nueva_publicacion_screen.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/widgets/tarjeta_publicacion.dart';

import '../utiles/foro_repository_falso.dart';
import '../utiles/fuente_cambios_foro_falsa.dart';

/// El foro (SCRUM-346) y el formulario para publicar en él (SCRUM-344 y
/// SCRUM-345).
void main() {
  // Viernes 16 de octubre de 2026.
  final ahora = DateTime(2026, 10, 16, 18);

  late ForoRepositorioFalso repositorio;
  late FuenteCambiosForoFalsa cambios;

  Future<void> abrirForo(
    WidgetTester tester, {
    List<PublicacionForo> publicaciones = const [],
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
    cambios = FuenteCambiosForoFalsa();
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
            GoRoute(
              path: 'rechazados',
              builder: (_, _) => const MisRechazadosScreen(),
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
          usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
          fuenteCambiosForoProvider.overrideWithValue(cambios),
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

    testWidgets('una publicación editada lo dice junto a la fecha', (
      tester,
    ) async {
      await abrirForo(
        tester,
        publicaciones: [
          publicacionDePrueba(
            fecha: DateTime(2026, 10, 16, 7),
            fechaEdicion: DateTime(2026, 10, 16, 9),
          ),
        ],
      );

      expect(find.text('Hoy • Editada'), findsOneWidget);
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

    testWidgets('si queda en revisión lo avisa y su autor la ve marcada', (
      tester,
    ) async {
      await abrirForo(tester);
      repositorio.estadoAlCrear = EstadoPublicacion.enRevision;
      await tester.tap(find.byKey(ForoScreen.claveNueva));
      await tester.pumpAndSettle();

      await escribir(tester, titulo: 'Oferta', contenido: 'Compra ya');
      await publicar(tester);

      expect(find.text(NuevaPublicacionScreen.enRevision), findsOneWidget);
      // SCRUM-322: su autor la ve arriba, marcada "En revisión".
      expect(find.text('Oferta'), findsOneWidget);
      expect(find.text(EstadoPublicacionChip.enRevision), findsOneWidget);
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

  group('en vivo (SCRUM-357)', () {
    final tenis = publicacionDePrueba(id: 'a', titulo: 'Tenis para asfalto');
    final ruta = publicacionDePrueba(id: 'b', titulo: 'Ruta en Las Palmas');

    /// Lo que pasa cuando otro usuario publica: la base ya tiene la fila y
    /// llega el aviso.
    Future<void> otroPublica(WidgetTester tester) async {
      repositorio.publicaciones.insert(0, ruta);
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
    }

    testWidgets('lo nuevo de otro espera detrás de un aviso y "Ver" lo '
        'muestra', (tester) async {
      await abrirForo(tester, publicaciones: [tenis]);

      await otroPublica(tester);

      expect(find.text('1 publicación nueva · Ver'), findsOneWidget);
      expect(find.text('Ruta en Las Palmas'), findsNothing);
      expect(find.text('Tenis para asfalto'), findsOneWidget);

      await tester.tap(find.byKey(ForoScreen.claveNuevas));
      await tester.pumpAndSettle();

      expect(find.text('Ruta en Las Palmas'), findsOneWidget);
      expect(find.byKey(ForoScreen.claveNuevas), findsNothing);
    });

    testWidgets('lo que publica uno mismo no se anuncia', (tester) async {
      await abrirForo(tester, publicaciones: [tenis]);

      repositorio.publicaciones.insert(0, ruta);
      cambios.emitirForo(
        const CambioForo(
          tipo: TipoCambioForo.nuevo,
          tabla: TablaForo.publicaciones,
          id: 'b',
          autorId: 'usuario-1',
        ),
      );
      await tester.pump(esperaCambiosForo);
      await tester.pumpAndSettle();

      expect(find.byKey(ForoScreen.claveNuevas), findsNothing);
      expect(find.text('Ruta en Las Palmas'), findsOneWidget);
    });

    testWidgets('una edición se ve en su sitio, sin refrescar', (tester) async {
      await abrirForo(tester, publicaciones: [tenis]);

      repositorio.publicaciones[0] = publicacionDePrueba(
        id: 'a',
        titulo: 'Tenis para asfalto y trail',
        fechaEdicion: ahora,
      );
      cambios.emitirForo(
        const CambioForo(
          tipo: TipoCambioForo.editado,
          tabla: TablaForo.publicaciones,
          id: 'a',
        ),
      );
      await tester.pump(esperaCambiosForo);
      await tester.pumpAndSettle();

      expect(find.text('Tenis para asfalto y trail'), findsOneWidget);
    });

    testWidgets('una ráfaga de avisos se resuelve con una sola consulta', (
      tester,
    ) async {
      await abrirForo(tester, publicaciones: [tenis]);
      final antes = repositorio.consultas;

      for (var i = 0; i < 5; i++) {
        cambios.emitirForo(
          const CambioForo(
            tipo: TipoCambioForo.nuevo,
            tabla: TablaForo.comentarios,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(esperaCambiosForo);
      await tester.pumpAndSettle();

      expect(repositorio.consultas - antes, 1);
    });

    testWidgets('al salir del foro deja de escuchar', (tester) async {
      await abrirForo(tester, publicaciones: [tenis]);
      expect(cambios.escuchandoForo, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(cambios.escuchandoForo, isFalse);
    });
  });

  group('botón de publicar', () {
    testWidgets('es un "+" flotante abajo a la derecha, no un botón arriba', (
      tester,
    ) async {
      await abrirForo(tester);

      final boton = find.byKey(ForoScreen.claveNueva);
      expect(
        find.descendant(of: boton, matching: find.byIcon(Icons.add)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
      final centro = tester.getCenter(boton);
      expect(centro.dx, greaterThan(pantalla.width / 2));
      expect(centro.dy, greaterThan(pantalla.height / 2));
    });

    testWidgets('al llegar al final, la última tarjeta queda por encima del '
        'botón', (tester) async {
      await abrirForo(
        tester,
        publicaciones: [
          for (var i = 0; i < 12; i++)
            publicacionDePrueba(id: 'p$i', titulo: 'Publicación $i'),
        ],
      );

      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      final ultima = tester.getRect(
        find.byKey(TarjetaPublicacion.claveDe('p11')),
      );
      final boton = tester.getRect(find.byKey(ForoScreen.claveNueva));
      expect(ultima.bottom, lessThanOrEqualTo(boton.top));
    });
  });

  group('rechazos (SCRUM-322)', () {
    final tenis = publicacionDePrueba(id: 'a', titulo: 'Tenis para asfalto');

    Finder contador(int n) =>
        find.descendant(of: find.byType(Badge), matching: find.text('$n'));

    testWidgets('cuenta los rechazos que el autor no ha visto', (tester) async {
      await abrirForo(
        tester,
        moderaciones: [
          moderacionDePrueba(id: 'm1'),
          moderacionDePrueba(id: 'm2'),
          moderacionDePrueba(id: 'm3', vistaPorAutor: true),
          moderacionDePrueba(id: 'm4', estado: EstadoModeracion.aprobada),
        ],
      );

      expect(contador(2), findsOneWidget);
    });

    testWidgets('al abrir "Mis rechazados" los marca como vistos y el '
        'contador desaparece', (tester) async {
      await abrirForo(tester, moderaciones: [moderacionDePrueba()]);

      await tester.tap(find.byKey(ForoScreen.claveRechazados));
      await tester.pumpAndSettle();

      expect(find.byType(MisRechazadosScreen), findsOneWidget);
      expect(repositorio.rechazosMarcados, 1);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(contador(1), findsNothing);
    });

    testWidgets('si la moderación rechaza algo propio, lo avisa en vivo con '
        'el motivo', (tester) async {
      await abrirForo(tester, publicaciones: [tenis]);

      repositorio.moderacionesGuardadas.add(moderacionDePrueba());
      cambios.emitirForo(
        const CambioForo(
          tipo: TipoCambioForo.editado,
          tabla: TablaForo.moderaciones,
          id: 'mod-1',
          autorId: 'usuario-1',
          estado: 'rechazada',
          motivo: 'Spam',
        ),
      );
      await tester.pump();
      await tester.pump(esperaCambiosForo);
      await tester.pumpAndSettle();

      expect(find.text(ForoScreen.textoRechazo('Spam')), findsOneWidget);
      expect(contador(1), findsOneWidget);
    });

    testWidgets('lo que la moderación le rechaza a otro no se le avisa', (
      tester,
    ) async {
      await abrirForo(tester, publicaciones: [tenis]);

      cambios.emitirForo(
        const CambioForo(
          tipo: TipoCambioForo.editado,
          tabla: TablaForo.moderaciones,
          autorId: 'otro-usuario',
          estado: 'rechazada',
          motivo: 'Spam',
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text(ForoScreen.textoRechazo('Spam')), findsNothing);
    });
  });
}
