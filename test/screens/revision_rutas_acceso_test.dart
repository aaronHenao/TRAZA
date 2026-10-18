import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/revision_ruta.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/screens/rutas/revision_rutas_screen.dart';
import 'package:traza/screens/rutas/rutas_revision.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/revision_rutas_service.dart';
import 'package:traza/services/rol_provider.dart';
import 'package:traza/services/roles_service.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/proveedor_tiles_falso.dart';
import '../utiles/revision_rutas_falso.dart';
import '../utiles/roles_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Rol de administrador fijo para la prueba.
class _RolFalso implements RolRepository {
  _RolFalso({required this.admin});

  final bool admin;

  @override
  Future<bool> esAdministrador() async => admin;
}

/// Acceso restringido a la revisión de rutas (SCRUM-332, criterio 7 de
/// SCRUM-321).
///
/// Monta las mismas rutas que `main.dart` (`rutasRevision`). Esto es la mitad
/// de presentación: la otra mitad, que la base no deje leer ni decidir a
/// quien no tiene el rol, está en las policies de `rutas` y en
/// `decidir_revision_ruta` (0036).
void main() {
  const soloAdmin = 'Esta sección es solo para administradores';
  const soloExperto = 'Esto es de Runner Experto';

  late RevisionRutasFalso revision;

  Future<void> entrar(
    WidgetTester tester,
    String ruta, {
    bool admin = false,
    bool experto = false,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final rutas = [
      rutaDePrueba(id: 'nueva'),
      rutaDePrueba(id: 'aprobada', estado: EstadoRuta.revisionExperto),
    ];
    revision = RevisionRutasFalso(rutas: rutas);

    final router = GoRouter(
      initialLocation: ruta,
      routes: [
        ...rutasRevision,
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Pantalla Inicio')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rolRepositoryProvider.overrideWithValue(_RolFalso(admin: admin)),
          rolesRepositoryProvider.overrideWithValue(
            experto ? RolesFalso.experto() : RolesFalso(),
          ),
          revisionRutasRepositoryProvider.overrideWithValue(revision),
          rutasRepositoryProvider.overrideWithValue(
            RutasRepositorioFalso(rutas: rutas),
          ),
          usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
          proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('un corredor sin roles', () {
    testWidgets('no entra a la bandeja del administrador', (tester) async {
      await entrar(tester, EtapaRevision.administrador.ruta);

      expect(find.text(soloAdmin), findsOneWidget);
      expect(find.byType(RevisionRutasScreen), findsNothing);
      // Ni siquiera se le pregunta a la base.
      expect(revision.consultas, 0);
    });

    testWidgets('no entra a la del Runner Experto', (tester) async {
      await entrar(tester, EtapaRevision.experto.ruta);

      expect(find.text(soloExperto), findsOneWidget);
      expect(find.byType(RevisionRutasScreen), findsNothing);
      expect(revision.consultas, 0);
    });

    testWidgets('tampoco abre una ruta por su direccion', (tester) async {
      await entrar(tester, EtapaRevision.administrador.detalleDe('nueva'));
      expect(find.text(soloAdmin), findsOneWidget);
      expect(find.byType(RevisionRutaScreen), findsNothing);
    });

    testWidgets('ni la del experto', (tester) async {
      await entrar(tester, EtapaRevision.experto.detalleDe('aprobada'));
      expect(find.text(soloExperto), findsOneWidget);
      expect(find.byType(RevisionRutaScreen), findsNothing);
    });

    testWidgets('puede volver al inicio', (tester) async {
      await entrar(tester, EtapaRevision.administrador.ruta);

      await tester.tap(find.text('Volver al inicio'));
      await tester.pumpAndSettle();

      expect(find.text('Pantalla Inicio'), findsOneWidget);
    });
  });

  group('el administrador', () {
    testWidgets('entra a su bandeja', (tester) async {
      await entrar(tester, EtapaRevision.administrador.ruta, admin: true);

      expect(find.byType(RevisionRutasScreen), findsOneWidget);
      expect(find.text('Revisión de rutas'), findsOneWidget);
    });

    testWidgets('no hace la revision del experto si no tiene el rol', (
      tester,
    ) async {
      await entrar(tester, EtapaRevision.experto.ruta, admin: true);

      expect(find.text(soloExperto), findsOneWidget);
    });
  });

  group('el Runner Experto', () {
    testWidgets('entra a su bandeja', (tester) async {
      await entrar(tester, EtapaRevision.experto.ruta, experto: true);

      expect(find.byType(RevisionRutasScreen), findsOneWidget);
      expect(find.text('Rutas por revisar'), findsOneWidget);
    });

    testWidgets('no hace la revision del administrador', (tester) async {
      await entrar(tester, EtapaRevision.administrador.ruta, experto: true);

      expect(find.text(soloAdmin), findsOneWidget);
    });
  });
}
