import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/screens/admin/gestion_retos_screen.dart';
import 'package:traza/services/rol_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/widgets/puerta_admin.dart';

class _RolFalso implements RolRepository {
  _RolFalso(this.respuesta);

  Future<bool> Function() respuesta;
  var consultas = 0;

  @override
  Future<bool> esAdministrador() {
    consultas++;
    return respuesta();
  }
}

class _RetosVacio implements RetosRepository {
  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async =>
      const [];

  @override
  Future<Reto> crear(NuevoReto reto) async => throw UnimplementedError();
}

/// Pruebas de la puerta que decide qué ve cada cuenta al entrar (SCRUM-139).
void main() {
  late _RolFalso rol;

  Future<void> abrir(
    WidgetTester tester, {
    required Future<bool> Function() esAdmin,
    bool esperar = true,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    rol = _RolFalso(esAdmin);
    final router = GoRouter(
      initialLocation: '/inicio',
      routes: [
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const PuertaAdmin(
            corredor: Scaffold(body: Text('Portada del corredor')),
          ),
        ),
        GoRoute(
          path: '/admin/retos/nuevo',
          builder: (_, _) => const Scaffold(body: Text('Formulario')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rolRepositoryProvider.overrideWithValue(rol),
          retosRepositoryProvider.overrideWithValue(_RetosVacio()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('la cuenta administradora entra a la gestión de retos', (
    tester,
  ) async {
    await abrir(tester, esAdmin: () async => true);

    expect(find.byType(GestionRetosScreen), findsOneWidget);
    expect(find.text('Portada del corredor'), findsNothing);
  });

  testWidgets('una cuenta normal ve su portada', (tester) async {
    await abrir(tester, esAdmin: () async => false);

    expect(find.text('Portada del corredor'), findsOneWidget);
    expect(find.byType(GestionRetosScreen), findsNothing);
  });

  testWidgets('mientras resuelve el rol no enseña ninguna de las dos', (
    tester,
  ) async {
    final pendiente = Completer<bool>();
    await abrir(tester, esAdmin: () => pendiente.future, esperar: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Portada del corredor'), findsNothing);

    pendiente.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Portada del corredor'), findsOneWidget);
  });

  testWidgets('si el rol no se puede leer, entra como corredor', (
    tester,
  ) async {
    // Al revés se abriría una gestión de retos que después no podría guardar
    // nada, porque RLS rechazaría la escritura.
    await abrir(tester, esAdmin: () async => throw Exception('sin red'));

    expect(find.text('Portada del corredor'), findsOneWidget);
  });

  testWidgets('el rol se consulta, no se supone', (tester) async {
    await abrir(tester, esAdmin: () async => true);

    expect(rol.consultas, 1);
  });
}
