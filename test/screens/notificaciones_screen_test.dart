import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/notificacion.dart';
import 'package:traza/screens/notificaciones/notificaciones_screen.dart';
import 'package:traza/services/cambios_notificaciones.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/notificaciones_service.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/fuente_cambios_notificaciones_falsa.dart';
import '../utiles/notificaciones_falso.dart';
import '../utiles/reloj_falso.dart';

/// Pruebas de la bandeja de notificaciones (SCRUM-241, SCRUM-242): qué
/// muestra, qué hace al abrirla y qué pasa si no se puede cargar.
void main() {
  final ahora = DateTime(2026, 10, 17, 12);

  group('lo que muestra', () {
    testWidgets('lista los avisos con su texto y cuándo llegaron', (
      tester,
    ) async {
      await _abrir(
        tester,
        notificaciones: [
          notificacionDePrueba(
            titulo: 'Tu ruta ya está publicada',
            mensaje: '"Vuelta al estadio" ya la puede ver la comunidad.',
            fechaCreacion: ahora,
          ),
          notificacionDePrueba(
            id: 'aviso-2',
            tipo: TipoNotificacion.publicacionRetirada,
            titulo: 'Retiramos tu publicación',
            mensaje: 'Motivo: lenguaje ofensivo.',
            fechaCreacion: DateTime(2026, 10, 16, 20),
            leidaEn: DateTime(2026, 10, 16, 21),
          ),
        ],
      );

      expect(find.text('Notificaciones'), findsOneWidget);
      expect(find.text('Tu ruta ya está publicada'), findsOneWidget);
      expect(
        find.text('"Vuelta al estadio" ya la puede ver la comunidad.'),
        findsOneWidget,
      );
      expect(find.text('Retiramos tu publicación'), findsOneWidget);
      expect(find.text('Motivo: lenguaje ofensivo.'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Ayer'), findsOneWidget);
    });

    testWidgets('aguanta el titulo y el mensaje mas largos que admite', (
      tester,
    ) async {
      // Los topes de `notificaciones`: 120 y 500 caracteres.
      await _abrir(
        tester,
        notificaciones: [
          notificacionDePrueba(titulo: 'T' * 120, mensaje: 'M' * 500),
        ],
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('muestra el aviso de que un Runner Experto clasificó la ruta '
        '(SCRUM-363)', (tester) async {
      await _abrir(
        tester,
        notificaciones: [
          notificacionDePrueba(
            tipo: TipoNotificacion.rutaClasificada,
            titulo: 'Tu ruta ya tiene dificultad',
            mensaje:
                'Un Runner Experto clasificó «Vuelta al estadio» como '
                'moderada. Confírmala para publicarla.',
            fechaCreacion: ahora,
          ),
        ],
      );

      expect(find.text('Tu ruta ya tiene dificultad'), findsOneWidget);
      expect(find.textContaining('Confírmala para publicarla'), findsOneWidget);
      expect(
        find.byIcon(TipoNotificacion.rutaClasificada.icono),
        findsOneWidget,
      );
    });

    testWidgets('sin avisos lo dice en vez de dejar la pantalla vacía', (
      tester,
    ) async {
      await _abrir(tester, notificaciones: const []);

      expect(find.text('No tienes notificaciones'), findsOneWidget);
      expect(find.byKey(NotificacionesScreen.claveLista), findsNothing);
    });

    testWidgets('si no carga, lo avisa y deja reintentar', (tester) async {
      final (repositorio: repositorio, router: _) = await _abrir(
        tester,
        notificaciones: const [],
        error: StateError('sin red'),
      );

      expect(find.text('No pudimos cargar tus notificaciones'), findsOneWidget);

      // Vuelve la conexión.
      repositorio.error = null;
      await tester.tap(find.byKey(NotificacionesScreen.claveReintentar));
      await tester.pumpAndSettle();

      expect(find.text('No tienes notificaciones'), findsOneWidget);
    });
  });

  group('abrirla es haberlas visto', () {
    testWidgets('las marca como leídas al cargar', (tester) async {
      final (repositorio: repositorio, router: _) = await _abrir(
        tester,
        notificaciones: [notificacionDePrueba()],
      );

      expect(repositorio.marcadas, 1);
      expect(await repositorio.sinLeer(), 0);
    });

    testWidgets('las que estaban sin leer siguen marcadas en pantalla', (
      tester,
    ) async {
      // La lista no se recarga a propósito: es lo que le deja ver al usuario
      // qué era nuevo mientras sigue en la bandeja.
      await _abrir(tester, notificaciones: [notificacionDePrueba()]);

      final icono = tester.widget<Icon>(
        find.byIcon(TipoNotificacion.rutaPublicada.icono),
      );
      expect(icono.color, isNot(equals(null)));
      expect(find.text('Tu ruta ya está publicada'), findsOneWidget);
    });

    testWidgets('volver a entrar vuelve a preguntar', (tester) async {
      // Un aviso puede llegar -o irse- mientras la app esta abierta en otra
      // pantalla, asi que la bandeja no se guarda para toda la sesion.
      final (repositorio: repositorio, router: router) = await _abrir(
        tester,
        notificaciones: [notificacionDePrueba()],
      );

      expect(repositorio.consultas, 1);

      router.pop();
      await tester.pumpAndSettle();
      router.push(NotificacionesScreen.ruta);
      await tester.pumpAndSettle();

      expect(repositorio.consultas, 2);
    });

    testWidgets('con la bandeja abierta, lo que llega entra solo', (
      tester,
    ) async {
      final (repositorio: repositorio, router: _) = await _abrir(
        tester,
        notificaciones: [notificacionDePrueba()],
      );

      expect(repositorio.consultas, 1);
      expect(cambiosAvisos.escuchando, isTrue);

      cambiosAvisos.emitir('usuario-1');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(repositorio.consultas, 2);
    });

    testWidgets('si no se pudo cargar, no da nada por visto', (tester) async {
      final (repositorio: repositorio, router: _) = await _abrir(
        tester,
        notificaciones: const [],
        error: StateError('sin red'),
      );

      expect(repositorio.marcadas, 0);
    });
  });
}

late FuenteCambiosNotificacionesFalsa cambiosAvisos;

Future<({NotificacionesFalso repositorio, GoRouter router})> _abrir(
  WidgetTester tester, {
  required List<Notificacion> notificaciones,
  Object? error,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio = NotificacionesFalso(
    notificaciones: notificaciones,
    error: error,
  );
  cambiosAvisos = FuenteCambiosNotificacionesFalsa();

  final router = GoRouter(
    initialLocation: '/origen',
    routes: [
      GoRoute(
        path: '/origen',
        builder: (_, _) => const Scaffold(body: Text('Pantalla de origen')),
      ),
      GoRoute(
        path: NotificacionesScreen.ruta,
        builder: (_, _) => const NotificacionesScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificacionesRepositoryProvider.overrideWithValue(repositorio),
        fuenteCambiosNotificacionesProvider.overrideWithValue(cambiosAvisos),
        usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
        relojProvider.overrideWithValue(
          RelojFalso(DateTime(2026, 10, 17, 12)).call,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.push(NotificacionesScreen.ruta);
  await tester.pumpAndSettle();

  return (repositorio: repositorio, router: router);
}
