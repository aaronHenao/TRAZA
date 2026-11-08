import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/admin/gestion_rutas_oficiales_screen.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;
import 'package:traza/services/rutas_oficiales_provider.dart';
import 'package:traza/services/rutas_oficiales_service.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/rutas_oficiales_repository_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Pruebas del módulo "Mapa de rutas oficiales" del administrador (rutas
/// oficiales, etapa 1): la lista del camino, agregar, subir, bajar y quitar.
void main() {
  final estadio = rutaDePrueba(
    id: 'ruta-estadio',
    nombre: 'Vuelta al estadio',
    autorNombre: 'Ana',
    estado: EstadoRuta.publicada,
    distanciaKm: 5.23,
    dificultad: Dificultad.facil,
  );
  final nutibara = rutaDePrueba(
    id: 'ruta-nutibara',
    nombre: 'Cerro Nutibara',
    autorNombre: 'Luis',
    estado: EstadoRuta.publicada,
    distanciaKm: 7.5,
    dificultad: Dificultad.dificil,
  );
  // Publicada sin dificultad: el criterio 2 admite que sea null.
  final rio = rutaDePrueba(
    id: 'ruta-rio',
    nombre: 'Parque del río',
    autorNombre: 'Sara',
    estado: EstadoRuta.publicada,
    distanciaKm: 3,
  );
  final circuito = rutaDePrueba(
    id: 'ruta-circuito',
    nombre: 'Circuito universitario',
    autorNombre: 'Marta',
    estado: EstadoRuta.publicada,
    distanciaKm: 10,
    dificultad: Dificultad.moderada,
  );
  final laureles = rutaDePrueba(
    id: 'ruta-laureles',
    nombre: 'Ciclovía de Laureles',
    autorNombre: 'Pedro',
    estado: EstadoRuta.publicada,
  );
  final enRevision = rutaDePrueba(
    id: 'ruta-en-revision',
    nombre: 'Todavía en revisión',
  );

  late RutasOficialesRepositorioFalso repositorio;

  Future<void> abrirGestion(
    WidgetTester tester, {
    List<Ruta>? oficiales,
    List<Ruta>? rutas,
    Object? errorAlListar,
    Object? errorAlListarPublicadas,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tabla =
        rutas ?? [estadio, nutibara, rio, circuito, laureles, enRevision];
    repositorio = RutasOficialesRepositorioFalso(
      oficiales: oficiales ?? [estadio, nutibara, rio],
      rutas: tabla,
    )..errorAlListar = errorAlListar;

    final router = GoRouter(
      initialLocation: GestionRutasOficialesScreen.ruta,
      routes: [
        GoRoute(
          path: GestionRutasOficialesScreen.ruta,
          builder: (_, _) => const GestionRutasOficialesScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rutasOficialesRepositoryProvider.overrideWithValue(repositorio),
          rutasRepositoryProvider.overrideWithValue(
            RutasRepositorioFalso(rutas: tabla, error: errorAlListarPublicadas),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fila(String id) =>
      find.byKey(GestionRutasOficialesScreen.claveFila(id));

  /// Algún texto de la fila de la ruta [id] que contiene [fragmento].
  Finder enLaFila(String id, String fragmento) =>
      find.descendant(of: fila(id), matching: find.textContaining(fragmento));

  /// La posición de la ruta [id]: un texto que es solo el número.
  Finder posicionEnLaFila(String id, int posicion) =>
      find.descendant(of: fila(id), matching: find.text('$posicion'));

  /// Si la fila de [arriba] se ve antes que la de [abajo].
  bool vaAntes(WidgetTester tester, String arriba, String abajo) =>
      tester.getTopLeft(fila(arriba)).dy < tester.getTopLeft(fila(abajo)).dy;

  /// Cualquier candidata del selector, sea de la ruta que sea.
  final algunaCandidata = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith(
          'candidata-ruta-oficial-',
        ),
  );

  Future<void> tocar(WidgetTester tester, Key clave) async {
    final boton = find.byKey(clave);
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  Future<void> abrirSelector(WidgetTester tester) =>
      tocar(tester, GestionRutasOficialesScreen.claveBotonAgregar);

  /// Comprueba que el botón de [clave] no está o está deshabilitado: que
  /// tocarlo no mueve nada.
  Future<void> expectNoDisponible(WidgetTester tester, Key clave) async {
    final boton = find.byKey(clave);
    if (boton.evaluate().isEmpty) return;

    final botones = find.descendant(
      of: boton,
      matching: find.byWidgetPredicate(
        (w) => w is IconButton || w is ButtonStyleButton,
      ),
      matchRoot: true,
    );
    expect(botones, findsWidgets, reason: '$clave debe ser un botón');
    for (final elemento in botones.evaluate()) {
      final onPressed = switch (elemento.widget) {
        final IconButton b => b.onPressed,
        final ButtonStyleButton b => b.onPressed,
        _ => null,
      };
      expect(onPressed, isNull, reason: '$clave debe estar deshabilitado');
    }

    await tester.tap(boton, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repositorio.movimientos, isEmpty);
  }

  group('la lista (criterio 2)', () {
    testWidgets('muestra cada ruta oficial con su posición, nombre, autor, '
        'distancia y dificultad', (tester) async {
      await abrirGestion(tester);

      expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
      expect(enLaFila('ruta-estadio', 'Vuelta al estadio'), findsOneWidget);
      expect(enLaFila('ruta-estadio', 'Ana'), findsOneWidget);
      expect(enLaFila('ruta-estadio', '5.23 km'), findsOneWidget);
      expect(enLaFila('ruta-estadio', 'Fácil'), findsOneWidget);

      expect(posicionEnLaFila('ruta-nutibara', 2), findsOneWidget);
      expect(enLaFila('ruta-nutibara', 'Cerro Nutibara'), findsOneWidget);
      expect(enLaFila('ruta-nutibara', 'Luis'), findsOneWidget);
      expect(enLaFila('ruta-nutibara', '7.5 km'), findsOneWidget);
      expect(enLaFila('ruta-nutibara', 'Difícil'), findsOneWidget);
    });

    testWidgets('una ruta sin dificultad sale como "Sin clasificar"', (
      tester,
    ) async {
      await abrirGestion(tester);

      expect(posicionEnLaFila('ruta-rio', 3), findsOneWidget);
      expect(enLaFila('ruta-rio', 'Parque del río'), findsOneWidget);
      expect(enLaFila('ruta-rio', '3 km'), findsOneWidget);
      expect(enLaFila('ruta-rio', 'Sin clasificar'), findsOneWidget);
    });

    testWidgets('las muestra en el orden de su posición', (tester) async {
      await abrirGestion(tester, oficiales: [nutibara, rio, estadio]);

      expect(vaAntes(tester, 'ruta-nutibara', 'ruta-rio'), isTrue);
      expect(vaAntes(tester, 'ruta-rio', 'ruta-estadio'), isTrue);
      expect(posicionEnLaFila('ruta-nutibara', 1), findsOneWidget);
      expect(posicionEnLaFila('ruta-rio', 2), findsOneWidget);
      expect(posicionEnLaFila('ruta-estadio', 3), findsOneWidget);
    });

    testWidgets('solo lista las oficiales, no las demás publicadas', (
      tester,
    ) async {
      await abrirGestion(tester);

      expect(fila('ruta-circuito'), findsNothing);
      expect(find.text('Circuito universitario'), findsNothing);
    });

    testWidgets('sin rutas oficiales muestra el estado vacío y deja agregar '
        'la primera', (tester) async {
      await abrirGestion(tester, oficiales: []);

      expect(find.text('Aún no hay rutas oficiales'), findsOneWidget);
      expect(fila('ruta-estadio'), findsNothing);
      expect(
        find.byKey(GestionRutasOficialesScreen.claveBotonAgregar),
        findsOneWidget,
      );
    });

    testWidgets('si la lista no carga, lo dice sin mostrar el error crudo y '
        'permite reintentar', (tester) async {
      await abrirGestion(
        tester,
        errorAlListar: Exception('Failed host lookup: proyecto.supabase.co'),
      );

      expect(
        find.text('No pudimos cargar las rutas oficiales'),
        findsOneWidget,
      );
      expect(find.textContaining('Failed host lookup'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);

      // Vuelve la conexión.
      repositorio.errorAlListar = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar las rutas oficiales'), findsNothing);
      expect(fila('ruta-estadio'), findsOneWidget);
    });
  });

  group('agregar (criterio 3)', () {
    testWidgets('si las publicadas no cargan, el selector lo dice sin el '
        'error crudo y no agrega nada', (tester) async {
      await abrirGestion(
        tester,
        errorAlListarPublicadas: Exception(
          'Failed host lookup: proyecto.supabase.co',
        ),
      );

      await abrirSelector(tester);

      expect(
        find.text('No pudimos cargar las rutas publicadas'),
        findsOneWidget,
      );
      expect(find.textContaining('Failed host lookup'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(repositorio.agregadas, isEmpty);
    });

    testWidgets('el botón abre un selector con las publicadas que todavía no '
        'son oficiales, y abrirlo no agrega nada', (tester) async {
      await abrirGestion(tester);

      await abrirSelector(tester);

      for (final (id, nombre) in [
        ('ruta-circuito', 'Circuito universitario'),
        ('ruta-laureles', 'Ciclovía de Laureles'),
      ]) {
        final candidata = find.byKey(
          GestionRutasOficialesScreen.claveCandidata(id),
        );
        expect(candidata, findsOneWidget, reason: id);
        expect(
          find.descendant(of: candidata, matching: find.textContaining(nombre)),
          findsOneWidget,
        );
      }
      // Ni las que ya son oficiales ni las que no están publicadas.
      for (final id in [
        'ruta-estadio',
        'ruta-nutibara',
        'ruta-rio',
        'ruta-en-revision',
      ]) {
        expect(
          find.byKey(GestionRutasOficialesScreen.claveCandidata(id)),
          findsNothing,
          reason: id,
        );
      }
      expect(repositorio.agregadas, isEmpty);
    });

    testWidgets('al tocar una candidata la agrega al final y la lista se '
        'refresca con ella', (tester) async {
      await abrirGestion(tester);
      await abrirSelector(tester);
      final consultas = repositorio.consultas;

      await tocar(
        tester,
        GestionRutasOficialesScreen.claveCandidata('ruta-circuito'),
      );

      expect(repositorio.agregadas, ['ruta-circuito']);
      expect(repositorio.consultas, greaterThan(consultas));
      expect(fila('ruta-circuito'), findsOneWidget);
      expect(posicionEnLaFila('ruta-circuito', 4), findsOneWidget);
      expect(
        enLaFila('ruta-circuito', 'Circuito universitario'),
        findsOneWidget,
      );
      expect(vaAntes(tester, 'ruta-rio', 'ruta-circuito'), isTrue);
      // Las que ya estaban no cambian de lugar.
      expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
    });

    testWidgets('si no hay candidatas, el selector lo dice', (tester) async {
      await abrirGestion(tester, rutas: [estadio, nutibara, rio, enRevision]);

      await abrirSelector(tester);

      expect(find.text('No hay rutas publicadas para agregar'), findsOneWidget);
      expect(algunaCandidata, findsNothing);
    });

    testWidgets('desde el estado vacío se agrega la primera', (tester) async {
      await abrirGestion(tester, oficiales: []);
      await abrirSelector(tester);

      await tocar(
        tester,
        GestionRutasOficialesScreen.claveCandidata('ruta-estadio'),
      );

      expect(repositorio.agregadas, ['ruta-estadio']);
      expect(find.text('Aún no hay rutas oficiales'), findsNothing);
      expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
    });
  });

  group('mover (criterio 4)', () {
    testWidgets('subir pide la posición anterior y la lista se refresca con '
        'el orden nuevo', (tester) async {
      await abrirGestion(tester);

      await tocar(
        tester,
        GestionRutasOficialesScreen.claveSubir('ruta-nutibara'),
      );

      expect(repositorio.movimientos, [('ruta-nutibara', 1)]);
      expect(posicionEnLaFila('ruta-nutibara', 1), findsOneWidget);
      expect(posicionEnLaFila('ruta-estadio', 2), findsOneWidget);
      expect(vaAntes(tester, 'ruta-nutibara', 'ruta-estadio'), isTrue);
    });

    testWidgets('bajar pide la posición siguiente y la lista se refresca con '
        'el orden nuevo', (tester) async {
      await abrirGestion(tester);

      await tocar(
        tester,
        GestionRutasOficialesScreen.claveBajar('ruta-nutibara'),
      );

      expect(repositorio.movimientos, [('ruta-nutibara', 3)]);
      expect(posicionEnLaFila('ruta-rio', 2), findsOneWidget);
      expect(posicionEnLaFila('ruta-nutibara', 3), findsOneWidget);
      expect(vaAntes(tester, 'ruta-rio', 'ruta-nutibara'), isTrue);
    });

    testWidgets('la primera no se puede subir, pero sí bajar', (tester) async {
      await abrirGestion(tester);

      await expectNoDisponible(
        tester,
        GestionRutasOficialesScreen.claveSubir('ruta-estadio'),
      );
      expect(
        find.byKey(GestionRutasOficialesScreen.claveBajar('ruta-estadio')),
        findsOneWidget,
      );
      expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
    });

    testWidgets('la última no se puede bajar, pero sí subir', (tester) async {
      await abrirGestion(tester);

      await expectNoDisponible(
        tester,
        GestionRutasOficialesScreen.claveBajar('ruta-rio'),
      );
      expect(
        find.byKey(GestionRutasOficialesScreen.claveSubir('ruta-rio')),
        findsOneWidget,
      );
      expect(posicionEnLaFila('ruta-rio', 3), findsOneWidget);
    });

    testWidgets('con una sola ruta no se puede subir ni bajar', (tester) async {
      await abrirGestion(tester, oficiales: [estadio]);
      // Sin esto, la prueba pasaría aunque la fila no existiera.
      expect(fila('ruta-estadio'), findsOneWidget);

      await expectNoDisponible(
        tester,
        GestionRutasOficialesScreen.claveSubir('ruta-estadio'),
      );
      await expectNoDisponible(
        tester,
        GestionRutasOficialesScreen.claveBajar('ruta-estadio'),
      );
    });
  });

  group('quitar (criterio 5)', () {
    final confirmar = find.byKey(
      GestionRutasOficialesScreen.claveConfirmarQuitar,
    );

    testWidgets('quitar pide confirmación y todavía no quita nada', (
      tester,
    ) async {
      await abrirGestion(tester);

      await tocar(
        tester,
        GestionRutasOficialesScreen.claveQuitar('ruta-estadio'),
      );

      expect(confirmar, findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(repositorio.quitadas, isEmpty);
    });

    testWidgets('al confirmar la quita y la lista se refresca: las de atrás '
        'suben una', (tester) async {
      await abrirGestion(tester);
      await tocar(
        tester,
        GestionRutasOficialesScreen.claveQuitar('ruta-estadio'),
      );

      await tocar(tester, GestionRutasOficialesScreen.claveConfirmarQuitar);

      expect(repositorio.quitadas, ['ruta-estadio']);
      expect(confirmar, findsNothing);
      expect(fila('ruta-estadio'), findsNothing);
      expect(posicionEnLaFila('ruta-nutibara', 1), findsOneWidget);
      expect(posicionEnLaFila('ruta-rio', 2), findsOneWidget);
    });

    testWidgets('al cancelar no se llama a quitar y la ruta sigue', (
      tester,
    ) async {
      await abrirGestion(tester);
      await tocar(
        tester,
        GestionRutasOficialesScreen.claveQuitar('ruta-estadio'),
      );

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(confirmar, findsNothing);
      expect(repositorio.quitadas, isEmpty);
      expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
    });

    testWidgets('cerrar la confirmación sin elegir tampoco quita', (
      tester,
    ) async {
      await abrirGestion(tester);
      await tocar(
        tester,
        GestionRutasOficialesScreen.claveQuitar('ruta-estadio'),
      );

      // Un toque fuera de la confirmación, sobre la barrera.
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(confirmar, findsNothing);
      expect(repositorio.quitadas, isEmpty);
      expect(fila('ruta-estadio'), findsOneWidget);
    });

    testWidgets('al quitar la única, muestra el estado vacío', (tester) async {
      await abrirGestion(tester, oficiales: [estadio]);
      await tocar(
        tester,
        GestionRutasOficialesScreen.claveQuitar('ruta-estadio'),
      );

      await tocar(tester, GestionRutasOficialesScreen.claveConfirmarQuitar);

      expect(repositorio.quitadas, ['ruta-estadio']);
      expect(find.text('Aún no hay rutas oficiales'), findsOneWidget);
    });
  });

  group('cuando la base no deja (criterio 6)', () {
    final errorCrudo = Exception('Failed host lookup: proyecto.supabase.co');

    /// El aviso con [mensaje] está en un SnackBar, y nada del error crudo
    /// está en la pantalla.
    void expectAvisoLegible(String mensaje) {
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(mensaje),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Failed host lookup'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Instance of'), findsNothing);
    }

    for (final (nombre, error, mensaje) in [
      (
        'SoloAdministradorException',
        const SoloAdministradorException(),
        GestionRutasOficiales.soloAdministrador,
      ),
      (
        'RutaNoPublicadaException',
        const RutaNoPublicadaException(),
        GestionRutasOficiales.noPublicada,
      ),
      (
        'RutaYaOficialException',
        const RutaYaOficialException(),
        GestionRutasOficiales.yaOficial,
      ),
      ('un error cualquiera', errorCrudo, GestionRutasOficiales.noSePudo),
    ]) {
      testWidgets('agregar: si el repositorio lanza $nombre, avisa "$mensaje" '
          'y la lista sigue igual', (tester) async {
        await abrirGestion(tester);
        await abrirSelector(tester);
        repositorio.errorAlCambiar = error;

        await tocar(
          tester,
          GestionRutasOficialesScreen.claveCandidata('ruta-circuito'),
        );

        expect(repositorio.agregadas, ['ruta-circuito']);
        expectAvisoLegible(mensaje);
        expect(fila('ruta-circuito'), findsNothing);
        expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
      });
    }

    for (final (nombre, error, mensaje) in [
      (
        'SoloAdministradorException',
        const SoloAdministradorException(),
        GestionRutasOficiales.soloAdministrador,
      ),
      ('un error cualquiera', errorCrudo, GestionRutasOficiales.noSePudo),
    ]) {
      testWidgets('subir: si el repositorio lanza $nombre, avisa "$mensaje" y '
          'el orden no cambia', (tester) async {
        await abrirGestion(tester);
        repositorio.errorAlCambiar = error;

        await tocar(
          tester,
          GestionRutasOficialesScreen.claveSubir('ruta-nutibara'),
        );

        expect(repositorio.movimientos, [('ruta-nutibara', 1)]);
        expectAvisoLegible(mensaje);
        expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
        expect(posicionEnLaFila('ruta-nutibara', 2), findsOneWidget);
      });

      testWidgets('bajar: si el repositorio lanza $nombre, avisa "$mensaje" y '
          'el orden no cambia', (tester) async {
        await abrirGestion(tester);
        repositorio.errorAlCambiar = error;

        await tocar(
          tester,
          GestionRutasOficialesScreen.claveBajar('ruta-nutibara'),
        );

        expect(repositorio.movimientos, [('ruta-nutibara', 3)]);
        expectAvisoLegible(mensaje);
        expect(posicionEnLaFila('ruta-nutibara', 2), findsOneWidget);
        expect(posicionEnLaFila('ruta-rio', 3), findsOneWidget);
      });

      testWidgets('quitar: si el repositorio lanza $nombre, avisa "$mensaje" '
          'y la ruta sigue', (tester) async {
        await abrirGestion(tester);
        repositorio.errorAlCambiar = error;
        await tocar(
          tester,
          GestionRutasOficialesScreen.claveQuitar('ruta-estadio'),
        );

        await tocar(tester, GestionRutasOficialesScreen.claveConfirmarQuitar);

        expect(repositorio.quitadas, ['ruta-estadio']);
        expectAvisoLegible(mensaje);
        expect(posicionEnLaFila('ruta-estadio', 1), findsOneWidget);
      });
    }
  });
}
