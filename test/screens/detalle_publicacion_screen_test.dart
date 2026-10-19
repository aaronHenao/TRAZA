import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/comentario_foro.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/models/reporte_foro.dart';
import 'package:traza/models/version_publicacion.dart';
import 'package:traza/screens/foro/detalle_publicacion_screen.dart';
import 'package:traza/screens/foro/editar_publicacion_screen.dart';
import 'package:traza/screens/foro/foro_screen.dart';
import 'package:traza/screens/foro/nueva_publicacion_screen.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/widgets/historial_versiones.dart';
import 'package:traza/widgets/tarjeta_publicacion.dart';

import '../utiles/foro_repository_falso.dart';
import '../utiles/fuente_cambios_foro_falsa.dart';

/// El detalle de una publicación con sus comentarios (SCRUM-351) y sus
/// validaciones (SCRUM-352), y la edición por su autor de publicaciones
/// (SCRUM-355) y comentarios (SCRUM-356).
void main() {
  final ahora = DateTime(2026, 10, 16, 18);

  late ForoRepositorioFalso repositorio;
  late FuenteCambiosForoFalsa cambios;

  Future<void> abrir(
    WidgetTester tester, {
    List<PublicacionForo>? publicaciones,
    bool vistaModeracion = false,
    String usuario = 'usuario-1',
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
    cambios = FuenteCambiosForoFalsa();

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
                vistaModeracion: vistaModeracion,
              ),
              routes: [
                GoRoute(
                  path: 'editar',
                  builder: (_, state) => EditarPublicacionScreen(
                    publicacionId: state.pathParameters['publicacionId']!,
                  ),
                ),
              ],
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
          usuarioActualProvider.overrideWithValue(() => usuario),
          fuenteCambiosForoProvider.overrideWithValue(cambios),
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
    expect(find.text('•'), findsOneWidget);
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

  testWidgets('una publicación rechazada no se puede comentar', (tester) async {
    await abrir(
      tester,
      publicaciones: [
        publicacionDePrueba(id: 'pub-1', estado: EstadoPublicacion.rechazada),
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
      ..rechazar('pub-1')
      ..errorAlComentar = const PublicacionNoDisponibleException();

    await comentar(tester, 'Llego tarde');

    expect(find.text(ComentarioPublicacion.noDisponible), findsOneWidget);
    expect(find.text(DetallePublicacionScreen.noDisponible), findsOneWidget);
    expect(find.byKey(DetallePublicacionScreen.claveCaja), findsNothing);
  });

  testWidgets('el administrador la ve aunque esté rechazada, sin caja', (
    tester,
  ) async {
    await abrir(
      tester,
      vistaModeracion: true,
      publicaciones: [
        publicacionDePrueba(
          id: 'pub-1',
          estado: EstadoPublicacion.rechazada,
          motivo: 'spam',
        ),
      ],
    );

    expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
    expect(find.text('Rechazada'), findsOneWidget);
    expect(find.text('Motivo: spam'), findsOneWidget);
    expect(find.byKey(DetallePublicacionScreen.claveCaja), findsNothing);
  });

  group('moderación para el autor (SCRUM-322)', () {
    testWidgets('su publicación en revisión la ve con el aviso y sin caja', (
      tester,
    ) async {
      await abrir(
        tester,
        usuario: 'autor-pub-1',
        publicaciones: [
          publicacionDePrueba(
            id: 'pub-1',
            estado: EstadoPublicacion.enRevision,
          ),
        ],
      );

      expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
      expect(
        find.text(DetallePublicacionScreen.publicacionEnRevision),
        findsOneWidget,
      );
      expect(find.byKey(DetallePublicacionScreen.claveCaja), findsNothing);
    });

    testWidgets('lo pendiente del administrador también le dice en revisión', (
      tester,
    ) async {
      await abrir(
        tester,
        usuario: 'autor-pub-1',
        publicaciones: [
          publicacionDePrueba(id: 'pub-1', estado: EstadoPublicacion.pendiente),
        ],
      );

      expect(
        find.text(DetallePublicacionScreen.publicacionEnRevision),
        findsOneWidget,
      );
      expect(find.text('Pendiente'), findsNothing);
    });

    testWidgets('si se la rechazaron ve el motivo', (tester) async {
      await abrir(
        tester,
        usuario: 'autor-pub-1',
        publicaciones: [
          publicacionDePrueba(
            id: 'pub-1',
            estado: EstadoPublicacion.rechazada,
            motivo: 'Spam',
          ),
        ],
      );

      expect(
        find.text(DetallePublicacionScreen.publicacionRechazada('Spam')),
        findsOneWidget,
      );
    });

    testWidgets('a los demás lo que está en revisión no les existe', (
      tester,
    ) async {
      await abrir(
        tester,
        publicaciones: [
          publicacionDePrueba(
            id: 'pub-1',
            estado: EstadoPublicacion.enRevision,
          ),
        ],
      );

      expect(find.text(DetallePublicacionScreen.noDisponible), findsOneWidget);
    });

    testWidgets('su comentario en revisión lo ve marcado; el rechazado no', (
      tester,
    ) async {
      await abrir(
        tester,
        preparar: (r) => r.comentariosDe['pub-1'] = [
          comentarioDePrueba(
            id: 'com-1',
            autorId: 'usuario-1',
            contenido: 'Esperando',
            estado: EstadoPublicacion.enRevision,
          ),
          comentarioDePrueba(
            id: 'com-2',
            autorId: 'usuario-1',
            contenido: 'Grosería',
            estado: EstadoPublicacion.rechazada,
          ),
        ],
      );

      expect(find.text('Esperando'), findsOneWidget);
      expect(find.text(EstadoPublicacionChip.enRevision), findsOneWidget);
      expect(find.text('Grosería'), findsNothing);
      // Lo que espera no se edita.
      expect(
        find.byKey(DetallePublicacionScreen.claveEditarComentario('com-1')),
        findsNothing,
      );
    });

    testWidgets('comentar avisa que el comentario quedó en revisión', (
      tester,
    ) async {
      await abrir(
        tester,
        preparar: (r) => r.estadoAlComentar = EstadoPublicacion.enRevision,
      );

      await comentar(tester, 'Buen dato');

      expect(find.text(ComentarioPublicacion.enRevision), findsOneWidget);
      expect(find.text('Buen dato'), findsOneWidget);
      expect(find.text(EstadoPublicacionChip.enRevision), findsOneWidget);
    });
  });

  group('insignias', () {
    testWidgets('el comentario del administrador dice Administrador', (
      tester,
    ) async {
      await abrir(
        tester,
        preparar: (r) => r.comentariosDe['pub-1'] = [
          comentarioDePrueba(
            id: 'com-1',
            autorNombre: 'David',
            autorEsAdmin: true,
          ),
          comentarioDePrueba(id: 'com-2', autorNombre: 'Lucía'),
        ],
      );

      expect(find.text(InsigniaForo.textoAdministrador), findsOneWidget);
      expect(find.text(InsigniaForo.textoAutor), findsNothing);
    });

    testWidgets('el creador de la publicación dice Autor en sus comentarios', (
      tester,
    ) async {
      await abrir(
        tester,
        preparar: (r) => r.comentariosDe['pub-1'] = [
          comentarioDePrueba(id: 'com-1', autorNombre: 'Lucía'),
          // `publicacionDePrueba(id: 'pub-1')` la escribió 'autor-pub-1'.
          comentarioDePrueba(
            id: 'com-2',
            autorId: 'autor-pub-1',
            autorNombre: 'Carlos',
          ),
        ],
      );

      expect(find.text(InsigniaForo.textoAutor), findsOneWidget);
      expect(find.text(InsigniaForo.textoAdministrador), findsNothing);
    });

    testWidgets('un corredor que no creó la publicación no lleva insignia', (
      tester,
    ) async {
      await abrir(
        tester,
        preparar: (r) => r.comentariosDe['pub-1'] = [comentarioDePrueba()],
      );

      expect(find.text(InsigniaForo.textoAdministrador), findsNothing);
      expect(find.text(InsigniaForo.textoAutor), findsNothing);
    });
  });

  testWidgets('una publicación del administrador dice Administrador junto a '
      'su nombre', (tester) async {
    await abrir(
      tester,
      publicaciones: [publicacionDePrueba(id: 'pub-1', autorEsAdmin: true)],
    );

    expect(find.text(InsigniaForo.textoAdministrador), findsOneWidget);
  });

  testWidgets(
    'el administrador comenta una publicada y sale como Administrador',
    (tester) async {
      await abrir(
        tester,
        vistaModeracion: true,
        preparar: (r) => r.comoAdmin = true,
      );

      expect(find.text('Publicada'), findsOneWidget);
      await comentar(tester, 'Recuerden hidratarse.');

      expect(find.text('Recuerden hidratarse.'), findsOneWidget);
      expect(find.text(InsigniaForo.textoAdministrador), findsOneWidget);
    },
  );

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

  group('editar (SCRUM-355)', () {
    // `publicacionDePrueba(id: 'pub-1')` la escribió 'autor-pub-1'.
    const autor = 'autor-pub-1';

    Future<void> editar(
      WidgetTester tester, {
      String? titulo,
      String? contenido,
    }) async {
      await tester.tap(find.byKey(DetallePublicacionScreen.claveEditar));
      await tester.pumpAndSettle();
      if (titulo != null) {
        await tester.enterText(
          find.byKey(NuevaPublicacionScreen.claveTitulo),
          titulo,
        );
      }
      if (contenido != null) {
        await tester.enterText(
          find.byKey(NuevaPublicacionScreen.claveContenido),
          contenido,
        );
      }
      await tester.tap(find.byKey(NuevaPublicacionScreen.clavePublicar));
      await tester.pumpAndSettle();
    }

    testWidgets('solo el autor ve el botón de editar', (tester) async {
      await abrir(tester);
      expect(find.byKey(DetallePublicacionScreen.claveEditar), findsNothing);
    });

    testWidgets('el autor abre el formulario con lo que había escrito', (
      tester,
    ) async {
      await abrir(tester, usuario: autor);

      await tester.tap(find.byKey(DetallePublicacionScreen.claveEditar));
      await tester.pumpAndSettle();

      expect(find.text('Editar publicación'), findsOneWidget);
      expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
    });

    testWidgets('antes de guardar pide confirmación; al confirmar los cambios '
        'quedan en revisión y se sigue viendo la versión anterior '
        '(SCRUM-322)', (tester) async {
      await abrir(tester, usuario: autor);

      await editar(tester, titulo: 'Tenis para asfalto y trail');

      expect(find.text('¿Guardar los cambios?'), findsOneWidget);
      expect(repositorio.edicionRecibida, isNull);

      await tester.tap(
        find.byKey(NuevaPublicacionScreen.claveConfirmarEdicion),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DetallePublicacionScreen), findsOneWidget);
      expect(repositorio.edicionRecibida?.titulo, 'Tenis para asfalto y trail');
      expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
      expect(find.text('Tenis para asfalto y trail'), findsNothing);
      expect(
        find.text(NuevaPublicacionScreen.edicionEnRevision),
        findsOneWidget,
      );
      expect(
        find.text(DetallePublicacionScreen.edicionEnRevision),
        findsOneWidget,
      );
      // Una edición a la vez.
      expect(find.byKey(DetallePublicacionScreen.claveEditar), findsNothing);
    });

    testWidgets('lo que edita el administrador se ve de una vez y todos ven '
        'que se editó, pero no su historial', (tester) async {
      await abrir(
        tester,
        usuario: autor,
        publicaciones: [publicacionDePrueba(id: 'pub-1', autorEsAdmin: true)],
        preparar: (r) => r.comoAdmin = true,
      );
      expect(find.text('Hoy • Editada'), findsNothing);

      await editar(tester, titulo: 'Tenis para asfalto y trail');
      await tester.tap(
        find.byKey(NuevaPublicacionScreen.claveConfirmarEdicion),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tenis para asfalto y trail'), findsOneWidget);
      expect(find.text(NuevaPublicacionScreen.editada), findsOneWidget);
      expect(find.text('Hoy • Editada'), findsOneWidget);
      expect(find.byKey(DetallePublicacionScreen.claveEditada), findsNothing);
    });

    testWidgets('con una edición en revisión no deja abrir otra', (
      tester,
    ) async {
      await abrir(
        tester,
        usuario: autor,
        preparar: (r) => r.moderacionesGuardadas.add(
          moderacionDePrueba(
            autorId: autor,
            accion: AccionModeracion.edicion,
            estado: EstadoModeracion.pendiente,
          ),
        ),
      );

      expect(find.byKey(DetallePublicacionScreen.claveEditar), findsNothing);
      expect(
        find.text(DetallePublicacionScreen.edicionEnRevision),
        findsOneWidget,
      );
    });

    testWidgets('el administrador abre el historial y ve cómo se leía', (
      tester,
    ) async {
      await abrir(
        tester,
        vistaModeracion: true,
        publicaciones: [
          publicacionDePrueba(
            id: 'pub-1',
            titulo: 'Tenis para asfalto y trail',
            fechaEdicion: DateTime(2026, 10, 16, 12),
          ),
        ],
        preparar: (r) => r.versionesDe['pub-1'] = [
          VersionPublicacion(
            id: 'ver-1',
            titulo: '¿Qué tenis para asfalto?',
            contenido: 'Busco recomendaciones para correr 10 km.',
            vigenteDesde: DateTime(2026, 10, 16, 8),
          ),
        ],
      );

      await tester.tap(find.byKey(DetallePublicacionScreen.claveEditada));
      await tester.pumpAndSettle();

      expect(find.text(HistorialVersiones.titulo), findsOneWidget);
      expect(find.textContaining('Versión 2 · actual'), findsOneWidget);
      expect(find.textContaining('Versión 1 · original'), findsOneWidget);
      // La de ahora en el detalle y en el historial; la original solo allí.
      expect(find.text('Tenis para asfalto y trail'), findsNWidgets(2));
      expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
    });

    testWidgets('si cancela, no se guarda nada y sigue editando', (
      tester,
    ) async {
      await abrir(tester, usuario: autor);

      await editar(tester, titulo: 'Otro título');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repositorio.edicionRecibida, isNull);
      expect(find.text('Editar publicación'), findsOneWidget);
      expect(find.text('Otro título'), findsOneWidget);
    });

    testWidgets('con un campo vacío no pregunta y marca el error', (
      tester,
    ) async {
      await abrir(tester, usuario: autor);

      await editar(tester, titulo: '   ');

      expect(find.text('¿Guardar los cambios?'), findsNothing);
      expect(find.text('Ponle un título a tu publicación.'), findsOneWidget);
      expect(repositorio.edicionRecibida, isNull);
    });

    testWidgets('sin cambios no pregunta', (tester) async {
      await abrir(tester, usuario: autor);

      await editar(tester);

      expect(find.text('¿Guardar los cambios?'), findsNothing);
      expect(find.text(NuevaPublicacionScreen.sinCambios), findsOneWidget);
    });

    testWidgets('si la rechazan mientras edita, lo avisa y no la cambia', (
      tester,
    ) async {
      await abrir(tester, usuario: autor);
      repositorio.errorAlEditar = const PublicacionNoDisponibleException();

      await editar(tester, titulo: 'Llego tarde');
      await tester.tap(
        find.byKey(NuevaPublicacionScreen.claveConfirmarEdicion),
      );
      await tester.pumpAndSettle();

      expect(find.text(EdicionPublicacion.noDisponible), findsOneWidget);
      expect(find.text('Llego tarde'), findsNothing);
    });

    testWidgets('lo rechazado no se ofrece para editar, ni a su autor', (
      tester,
    ) async {
      await abrir(
        tester,
        usuario: autor,
        vistaModeracion: true,
        publicaciones: [
          publicacionDePrueba(id: 'pub-1', estado: EstadoPublicacion.rechazada),
        ],
      );

      expect(find.byKey(DetallePublicacionScreen.claveEditar), findsNothing);
    });
  });

  group('editar comentarios (SCRUM-356)', () {
    ComentarioForo mio({DateTime? fechaEdicion}) => comentarioDePrueba(
      id: 'com-1',
      autorId: 'usuario-1',
      autorNombre: 'Ana Runner',
      contenido: 'Prueba con unos Pegasus.',
      fechaEdicion: fechaEdicion,
    );

    Future<void> editarComentario(WidgetTester tester, String texto) async {
      await tester.tap(
        find.byKey(DetallePublicacionScreen.claveEditarComentario('com-1')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(DetallePublicacionScreen.claveCajaEdicion),
        texto,
      );
      await tester.tap(
        find.byKey(DetallePublicacionScreen.claveGuardarEdicion),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('solo el autor del comentario ve el botón de editar', (
      tester,
    ) async {
      await abrir(
        tester,
        preparar: (r) => r.comentariosDe['pub-1'] = [
          mio(),
          comentarioDePrueba(id: 'com-2', autorNombre: 'Lucía'),
        ],
      );

      expect(
        find.byKey(DetallePublicacionScreen.claveEditarComentario('com-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(DetallePublicacionScreen.claveEditarComentario('com-2')),
        findsNothing,
      );
    });

    testWidgets('pide confirmación y al guardar el cambio queda en revisión '
        'con el texto anterior a la vista (SCRUM-322)', (tester) async {
      await abrir(tester, preparar: (r) => r.comentariosDe['pub-1'] = [mio()]);

      await editarComentario(tester, 'Mejor unos Novablast.');

      expect(find.text('¿Guardar los cambios?'), findsOneWidget);
      expect(repositorio.edicionComentarioRecibida, isNull);

      await tester.tap(
        find.byKey(DetallePublicacionScreen.claveConfirmarEdicionComentario),
      );
      await tester.pumpAndSettle();

      expect(
        repositorio.edicionComentarioRecibida?.contenido,
        'Mejor unos Novablast.',
      );
      expect(find.text('Prueba con unos Pegasus.'), findsOneWidget);
      expect(find.text('Mejor unos Novablast.'), findsNothing);
      expect(
        find.text(DetallePublicacionScreen.comentarioEnRevision),
        findsOneWidget,
      );
      expect(
        find.text(DetallePublicacionScreen.edicionComentarioEnRevision),
        findsOneWidget,
      );
      expect(
        find.byKey(DetallePublicacionScreen.claveEditarComentario('com-1')),
        findsNothing,
      );
    });

    testWidgets('lo que edita el administrador queda de una vez marcado como '
        'editado', (tester) async {
      await abrir(
        tester,
        preparar: (r) {
          r.comoAdmin = true;
          r.comentariosDe['pub-1'] = [
            comentarioDePrueba(
              id: 'com-1',
              autorId: 'usuario-1',
              autorNombre: 'Ana Runner',
              contenido: 'Prueba con unos Pegasus.',
              autorEsAdmin: true,
            ),
          ];
        },
      );

      await editarComentario(tester, 'Mejor unos Novablast.');
      await tester.tap(
        find.byKey(DetallePublicacionScreen.claveConfirmarEdicionComentario),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mejor unos Novablast.'), findsOneWidget);
      expect(find.text('Prueba con unos Pegasus.'), findsNothing);
      expect(find.text('Hoy • Editado'), findsOneWidget);
      expect(
        find.text(DetallePublicacionScreen.comentarioEditado),
        findsOneWidget,
      );
      // Fuera de la moderación no se abre el historial.
      expect(
        find.byKey(DetallePublicacionScreen.claveComentarioEditado('com-1')),
        findsNothing,
      );
    });

    testWidgets('si cancela la confirmación no cambia nada', (tester) async {
      await abrir(tester, preparar: (r) => r.comentariosDe['pub-1'] = [mio()]);

      await editarComentario(tester, 'Mejor unos Novablast.');
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();

      expect(repositorio.edicionComentarioRecibida, isNull);
    });

    testWidgets('vacío no pregunta y dice que no puede estar vacío', (
      tester,
    ) async {
      await abrir(tester, preparar: (r) => r.comentariosDe['pub-1'] = [mio()]);

      await editarComentario(tester, '   ');

      expect(find.text('¿Guardar los cambios?'), findsNothing);
      expect(find.text('El comentario no puede estar vacío.'), findsOneWidget);
      expect(repositorio.edicionComentarioRecibida, isNull);
    });

    testWidgets('en una publicación rechazada no se ofrece editar', (
      tester,
    ) async {
      await abrir(
        tester,
        vistaModeracion: true,
        publicaciones: [
          publicacionDePrueba(id: 'pub-1', estado: EstadoPublicacion.rechazada),
        ],
        preparar: (r) => r.comentariosDe['pub-1'] = [mio()],
      );

      expect(
        find.byKey(DetallePublicacionScreen.claveEditarComentario('com-1')),
        findsNothing,
      );
    });

    testWidgets('el administrador abre el historial del comentario en un '
        'modal', (tester) async {
      await abrir(
        tester,
        vistaModeracion: true,
        usuario: 'admin-1',
        preparar: (r) => r
          ..comentariosDe['pub-1'] = [
            comentarioDePrueba(
              id: 'com-1',
              contenido: 'Mejor unos Novablast.',
              fechaEdicion: DateTime(2026, 10, 16, 12),
            ),
          ]
          ..versionesComentarioDe['com-1'] = [
            VersionComentario(
              id: 'vc-1',
              contenido: 'Prueba con unos Pegasus.',
              vigenteDesde: DateTime(2026, 10, 16, 10),
            ),
          ],
      );

      await tester.tap(
        find.byKey(DetallePublicacionScreen.claveComentarioEditado('com-1')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(HistorialVersiones.titulo), findsOneWidget);
      expect(find.textContaining('Versión 1 · original'), findsOneWidget);
      expect(find.text('Prueba con unos Pegasus.'), findsOneWidget);
    });
  });

  group('en vivo (SCRUM-357)', () {
    testWidgets('el comentario de otro aparece solo y no borra lo que se '
        'está escribiendo', (tester) async {
      await abrir(tester);
      await tester.enterText(
        find.byKey(DetallePublicacionScreen.claveCaja),
        'Yo uso unos',
      );

      repositorio.comentariosDe['pub-1'] = [
        comentarioDePrueba(autorNombre: 'Lucía', contenido: 'Prueba Pegasus.'),
      ];
      cambios.emitirPublicacion(
        'pub-1',
        const CambioForo(
          tipo: TipoCambioForo.nuevo,
          tabla: TablaForo.comentarios,
          id: 'com-1',
          publicacionId: 'pub-1',
        ),
      );
      await tester.pump(esperaCambiosForo);
      await tester.pumpAndSettle();

      expect(find.text('Prueba Pegasus.'), findsOneWidget);
      expect(find.text('COMENTARIOS (1)'), findsOneWidget);
      final caja = tester.widget<TextField>(
        find.byKey(DetallePublicacionScreen.claveCaja),
      );
      expect(caja.controller!.text, 'Yo uso unos');
    });

    testWidgets('si la rechazan, el detalle se entera sin refrescar', (
      tester,
    ) async {
      await abrir(tester);

      repositorio.rechazar('pub-1');
      cambios.emitirPublicacion(
        'pub-1',
        const CambioForo(tipo: TipoCambioForo.reconectado),
      );
      await tester.pump(esperaCambiosForo);
      await tester.pumpAndSettle();

      expect(find.text(DetallePublicacionScreen.noDisponible), findsOneWidget);
      expect(find.byKey(DetallePublicacionScreen.claveCaja), findsNothing);
    });

    testWidgets('escucha solo mientras el detalle está abierto', (
      tester,
    ) async {
      await abrir(tester);
      expect(cambios.escuchandoPublicacion, isTrue);

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(cambios.escuchandoPublicacion, isFalse);
    });
  });

  group('reportar (SCRUM-369)', () {
    // `publicacionDePrueba(id: 'pub-1')` la escribió 'autor-pub-1'; quien
    // abre el detalle por defecto es 'usuario-1', el mismo
    // `ForoRepositorioFalso.usuario` que el doble anota como reportante.
    const autor = 'autor-pub-1';

    final dialogo = find.byType(AlertDialog);

    Future<void> abrirReporte(WidgetTester tester) async {
      await tester.tap(find.byKey(DetallePublicacionScreen.claveReportar));
      await tester.pumpAndSettle();
    }

    Future<void> elegir(WidgetTester tester, MotivoReporte motivo) async {
      final opcion = find.byKey(
        DetallePublicacionScreen.claveMotivoReporte(motivo),
      );
      await tester.ensureVisible(opcion);
      await tester.pumpAndSettle();
      await tester.tap(opcion);
      await tester.pumpAndSettle();
    }

    Future<void> escribirDetalle(WidgetTester tester, String texto) async {
      final caja = find.byKey(DetallePublicacionScreen.claveDetalleReporte);
      await tester.ensureVisible(caja);
      await tester.enterText(caja, texto);
      await tester.pump();
    }

    Future<void> enviar(WidgetTester tester) async {
      await tester.tap(find.byKey(DetallePublicacionScreen.claveEnviarReporte));
      await tester.pumpAndSettle();
    }

    Future<void> reportar(WidgetTester tester, MotivoReporte motivo) async {
      await abrirReporte(tester);
      await elegir(tester, motivo);
      await enviar(tester);
    }

    bool enviarHabilitado(WidgetTester tester) {
      final boton = tester.widget(
        find.byKey(DetallePublicacionScreen.claveEnviarReporte),
      );
      return boton is ButtonStyleButton && boton.enabled;
    }

    /// Los reportes que el doble guardó a nombre del usuario de la sesión.
    Iterable<ReporteForo> delUsuario() => repositorio.reportesGuardados.where(
      (r) =>
          r.publicacionId == 'pub-1' &&
          repositorio.reportanteDe[r.id] == ForoRepositorioFalso.usuario,
    );

    testWidgets('el corredor ve la opción de reportar en lo publicado por '
        'otro (criterio 1 de SCRUM-369)', (tester) async {
      await abrir(tester);

      final boton = find.byKey(DetallePublicacionScreen.claveReportar);
      expect(boton, findsOneWidget);
      expect(find.byTooltip('Reportar publicación'), findsOneWidget);
      expect(
        find.descendant(of: boton, matching: find.byIcon(Icons.flag_outlined)),
        findsOneWidget,
      );
      expect(find.byKey(DetallePublicacionScreen.claveEditar), findsNothing);
    });

    testWidgets('al autor no se le ofrece reportar lo suyo, sino editarlo', (
      tester,
    ) async {
      await abrir(tester, usuario: autor);

      expect(find.byKey(DetallePublicacionScreen.claveReportar), findsNothing);
      expect(find.byKey(DetallePublicacionScreen.claveEditar), findsOneWidget);
    });

    testWidgets('lo propio que espera la moderación tampoco se reporta', (
      tester,
    ) async {
      await abrir(
        tester,
        usuario: autor,
        publicaciones: [
          publicacionDePrueba(
            id: 'pub-1',
            estado: EstadoPublicacion.enRevision,
          ),
        ],
      );

      expect(find.byKey(DetallePublicacionScreen.claveReportar), findsNothing);
    });

    testWidgets('en la moderación no se ofrece reportar', (tester) async {
      await abrir(tester, vistaModeracion: true, usuario: 'admin-1');

      expect(find.text('Publicada'), findsOneWidget);
      expect(find.byKey(DetallePublicacionScreen.claveReportar), findsNothing);
    });

    testWidgets('elegir el motivo y enviar registra el reporte y confirma que '
        'se recibió, sin nombrar a nadie (criterios 1 y 2 de SCRUM-369)', (
      tester,
    ) async {
      await abrir(tester);

      await abrirReporte(tester);
      expect(
        find.descendant(
          of: dialogo,
          matching: find.text('Reportar publicación'),
        ),
        findsOneWidget,
      );
      for (final motivo in MotivoReporte.values) {
        expect(
          find.byKey(DetallePublicacionScreen.claveMotivoReporte(motivo)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialogo, matching: find.text(motivo.etiqueta)),
          findsOneWidget,
        );
      }

      await elegir(tester, MotivoReporte.acoso);
      await escribirDetalle(tester, 'Insulta en los comentarios');
      await enviar(tester);

      final reporte = delUsuario().single;
      expect(reporte.motivo, MotivoReporte.acoso);
      expect(reporte.detalle, 'Insulta en los comentarios');
      expect(dialogo, findsNothing);
      expect(find.text(ReportePublicacion.recibido), findsOneWidget);
      // Nada en pantalla dice quién reportó.
      expect(find.textContaining(ForoRepositorioFalso.usuario), findsNothing);
      expect(find.textContaining('Ana Runner'), findsNothing);
    });

    testWidgets('Enviar no se activa hasta elegir un motivo', (tester) async {
      await abrir(tester);
      await abrirReporte(tester);

      expect(enviarHabilitado(tester), isFalse);
      await tester.tap(
        find.byKey(DetallePublicacionScreen.claveEnviarReporte),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(repositorio.reporteRecibido, isNull);
      expect(dialogo, findsOneWidget);

      await elegir(tester, MotivoReporte.spam);

      expect(enviarHabilitado(tester), isTrue);
    });

    testWidgets('si ya la reportó, no registra un segundo reporte y avisa que '
        'está en revisión (criterio 3 de SCRUM-369)', (tester) async {
      await abrir(tester);
      await reportar(tester, MotivoReporte.acoso);
      expect(find.text(ReportePublicacion.recibido), findsOneWidget);

      await reportar(tester, MotivoReporte.spam);

      expect(find.text(ReportePublicacion.duplicado), findsOneWidget);
      expect(delUsuario(), hasLength(1));
      expect(delUsuario().single.motivo, MotivoReporte.acoso);
    });

    testWidgets('cancelar no registra nada', (tester) async {
      await abrir(tester);
      await abrirReporte(tester);
      await elegir(tester, MotivoReporte.spam);

      await tester.tap(
        find.descendant(of: dialogo, matching: find.text('Cancelar')),
      );
      await tester.pumpAndSettle();

      expect(dialogo, findsNothing);
      expect(repositorio.reporteRecibido, isNull);
      expect(repositorio.reportesGuardados, isEmpty);
      expect(find.text(ReportePublicacion.recibido), findsNothing);
    });

    testWidgets('con el motivo "Otro" pide contar por qué antes de enviar', (
      tester,
    ) async {
      await abrir(tester);
      await abrirReporte(tester);
      await elegir(tester, MotivoReporte.otro);
      await escribirDetalle(tester, '   ');

      await enviar(tester);

      expect(find.text(ReportePublicacion.sinDetalle), findsOneWidget);
      expect(repositorio.reporteRecibido, isNull);
      expect(dialogo, findsOneWidget);

      await escribirDetalle(tester, 'Publica el teléfono de otra corredora');
      await enviar(tester);

      expect(delUsuario().single.motivo, MotivoReporte.otro);
      expect(find.text(ReportePublicacion.recibido), findsOneWidget);
    });

    testWidgets('el detalle no pasa del límite de la base', (tester) async {
      await abrir(tester);
      await abrirReporte(tester);

      await escribirDetalle(tester, 'a' * (maxCaracteresDetalleReporte + 20));

      final texto = tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(DetallePublicacionScreen.claveDetalleReporte),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(texto.length, maxCaracteresDetalleReporte);
    });

    testWidgets('si la publicación dejó de estar publicada, lo avisa', (
      tester,
    ) async {
      await abrir(tester);
      repositorio.rechazar('pub-1');

      await reportar(tester, MotivoReporte.spam);

      expect(find.text(ReportePublicacion.noDisponible), findsOneWidget);
      expect(repositorio.reportesGuardados, isEmpty);
    });

    testWidgets('si dejó de estar publicada, el detalle se actualiza y deja de '
        'ofrecer reportarla', (tester) async {
      await abrir(tester);
      repositorio.rechazar('pub-1');

      await reportar(tester, MotivoReporte.spam);

      expect(find.text(DetallePublicacionScreen.noDisponible), findsOneWidget);
      expect(find.byKey(DetallePublicacionScreen.claveReportar), findsNothing);
    });

    testWidgets('un fallo de red avisa que no se pudo enviar', (tester) async {
      await abrir(
        tester,
        preparar: (r) => r.errorAlReportar = Exception('sin red'),
      );

      await reportar(tester, MotivoReporte.spam);

      expect(find.text(ReportePublicacion.noSePudo), findsOneWidget);
    });

    testWidgets('al autor de una publicación reportada no se le dice que la '
        'reportaron ni quién (criterio 2 de SCRUM-369)', (tester) async {
      await abrir(
        tester,
        usuario: autor,
        preparar: (r) {
          r.reportesGuardados.add(reporteDePrueba(id: 'rep-1'));
          r.reportanteDe['rep-1'] = ForoRepositorioFalso.usuario;
        },
      );

      expect(find.text('¿Qué tenis para asfalto?'), findsOneWidget);
      expect(
        find.textContaining(RegExp('report', caseSensitive: false)),
        findsNothing,
      );
      expect(find.textContaining(ForoRepositorioFalso.usuario), findsNothing);
    });
  });
}
