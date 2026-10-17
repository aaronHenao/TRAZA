import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/publicacion_foro.dart';
import 'package:traza/screens/admin/moderacion_foro_screen.dart';
import 'package:traza/screens/foro/nueva_publicacion_screen.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/reloj_provider.dart';
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
    List<PublicacionForo> publicaciones,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = ForoRepositorioFalso(publicaciones: publicaciones);
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
      estado: EstadoPublicacion.retenida,
      motivo: 'spam',
    ),
  ];

  testWidgets('abre en lo publicado y cuenta cada estado', (tester) async {
    await abrir(tester, publicaciones);

    expect(find.text('Publicadas (1)'), findsOneWidget);
    expect(find.text('Retenidas (1)'), findsOneWidget);
    expect(find.text('Tenis para asfalto'), findsOneWidget);
    expect(find.text('Gana dinero fácil'), findsNothing);
  });

  testWidgets('en retenidas muestra el estado y el motivo', (tester) async {
    await abrir(tester, publicaciones);

    await tester.tap(
      find.byKey(
        ModeracionForoScreen.claveVista(VistaModeracionForo.retenidas),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Gana dinero fácil'), findsOneWidget);
    expect(find.text('Retenida'), findsOneWidget);
    expect(find.text('Motivo: spam'), findsOneWidget);
    expect(find.text('Tenis para asfalto'), findsNothing);
  });

  testWidgets('sin retenidas aclara que la moderación aún no está activa', (
    tester,
  ) async {
    await abrir(tester, [publicacionDePrueba()]);

    await tester.tap(
      find.byKey(
        ModeracionForoScreen.claveVista(VistaModeracionForo.retenidas),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No hay publicaciones retenidas'), findsOneWidget);
    expect(
      find.textContaining('La moderación automática todavía no está activa'),
      findsOneWidget,
    );
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
