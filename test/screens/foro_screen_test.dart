import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/borrador_publicacion.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/foro/foro_screen.dart';
import 'package:traza/screens/foro/nueva_publicacion_screen.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/rutas_service.dart';
import 'package:traza/widgets/tarjeta_ruta.dart';

import '../utiles/foro_repository_falso.dart';
import '../utiles/fuente_cambios_foro_falsa.dart';
import '../utiles/rutas_repository_falso.dart';

/// El foro (SCRUM-346) y el formulario para publicar en él (SCRUM-344 y
/// SCRUM-345).
void main() {
  // Viernes 16 de octubre de 2026.
  final ahora = DateTime(2026, 10, 16, 18);

  late ForoRepositorioFalso repositorio;
  late FuenteCambiosForoFalsa cambios;
  late RutasRepositorioFalso rutas;

  Future<void> abrirForo(
    WidgetTester tester, {
    List<PublicacionForo> publicaciones = const [],
    List<Ruta> rutasPublicadas = const [],
    Object? errorDeRutas,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = ForoRepositorioFalso(
      publicaciones: publicaciones,
      ahora: ahora,
    );
    cambios = FuenteCambiosForoFalsa();
    rutas = RutasRepositorioFalso(rutas: rutasPublicadas, error: errorDeRutas);
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
          usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
          fuenteCambiosForoProvider.overrideWithValue(cambios),
          rutasRepositoryProvider.overrideWithValue(rutas),
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

  group('apartado de rutas (SCRUM-241)', () {
    Ruta ruta({
      String id = 'ruta-1',
      String nombre = 'Vuelta al Parque Norte',
      String autor = 'Ana',
      double? distanciaKm = 5.23,
      DateTime? publicada,
    }) => Ruta(
      id: id,
      autorId: 'usuario-9',
      autorNombre: autor,
      nombre: nombre,
      estado: EstadoRuta.publicada,
      distanciaKm: distanciaKm,
      fechaCreacion: DateTime(2026, 10, 15),
      fechaPublicacion: publicada ?? DateTime(2026, 10, 16, 9),
    );

    Future<void> verRutas(WidgetTester tester) async {
      await tester.tap(find.byKey(ForoScreen.claveSeccion(SeccionForo.rutas)));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra cada ruta con su autor, su fecha y su distancia', (
      tester,
    ) async {
      await abrirForo(
        tester,
        rutasPublicadas: [
          ruta(),
          ruta(id: 'ruta-2', nombre: 'Cerro', autor: 'Luis'),
        ],
      );

      await verRutas(tester);

      expect(find.byType(TarjetaRuta), findsNWidgets(2));
      expect(find.text('Vuelta al Parque Norte'), findsOneWidget);
      // El criterio 4: de quien es y de cuando.
      expect(find.text('Por Ana · Hoy'), findsOneWidget);
      expect(find.text('Por Luis · Hoy'), findsOneWidget);
      expect(find.text('5.23 km'), findsNWidgets(2));
    });

    testWidgets('una ruta sin distancia registrada lo dice (SCRUM-240)', (
      tester,
    ) async {
      await abrirForo(tester, rutasPublicadas: [ruta(distanciaKm: null)]);

      await verRutas(tester);

      expect(find.text(TarjetaRuta.sinDistancia), findsOneWidget);
    });

    testWidgets('sin rutas explica de donde salen', (tester) async {
      await abrirForo(tester);

      await verRutas(tester);

      expect(find.text('Todavía no hay rutas publicadas'), findsOneWidget);
      expect(
        find.textContaining('publica su recorrido desde el resumen'),
        findsOneWidget,
      );
    });

    testWidgets('ahi no se ofrece redactar un tema', (tester) async {
      // Una ruta no se escribe en el foro: se publica desde el resumen del
      // entrenamiento que la grabo.
      await abrirForo(tester, rutasPublicadas: [ruta()]);

      expect(find.byKey(ForoScreen.claveNueva), findsOneWidget);
      await verRutas(tester);
      expect(find.byKey(ForoScreen.claveNueva), findsNothing);
    });

    testWidgets('si no cargan, deja reintentar', (tester) async {
      await abrirForo(tester, errorDeRutas: StateError('sin red'));

      await verRutas(tester);

      expect(find.text('No pudimos cargar las rutas'), findsOneWidget);

      rutas.error = null;
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Todavía no hay rutas publicadas'), findsOneWidget);
    });

    testWidgets('los temas siguen estando a un chip', (tester) async {
      await abrirForo(
        tester,
        publicaciones: [
          PublicacionForo(
            id: 'pub-1',
            autorId: 'usuario-2',
            autorNombre: 'Camila',
            titulo: 'Zapatillas para trail',
            contenido: '¿Cuáles usan?',
            estado: EstadoPublicacion.publicada,
            fechaCreacion: DateTime(2026, 10, 16, 16),
          ),
        ],
        rutasPublicadas: [ruta()],
      );

      await verRutas(tester);
      expect(find.text('Zapatillas para trail'), findsNothing);

      await tester.tap(find.byKey(ForoScreen.claveSeccion(SeccionForo.temas)));
      await tester.pumpAndSettle();

      expect(find.text('Zapatillas para trail'), findsOneWidget);
      expect(find.byType(TarjetaRuta), findsNothing);
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
}
