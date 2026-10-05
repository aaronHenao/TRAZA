import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/services/rol_provider.dart';
import 'package:traza/widgets/solo_administrador.dart';

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

/// Pruebas de la barrera de las pantallas de administración (SCRUM-183).
///
/// Es la mitad de presentación del control de acceso. La otra mitad, que la
/// base rechace una escritura directa aunque la interfaz se salte, la cubre
/// `niveles_service_test.dart` con el código 42501 de RLS.
void main() {
  late _RolFalso rol;

  Future<void> abrir(
    WidgetTester tester, {
    required Future<bool> Function() esAdmin,
    bool esperar = true,
  }) async {
    rol = _RolFalso(esAdmin);
    final router = GoRouter(
      initialLocation: '/admin/niveles',
      routes: [
        GoRoute(
          path: '/admin/niveles',
          builder: (_, _) => const SoloAdministrador(
            hijo: Scaffold(body: Text('Gestión de niveles')),
          ),
        ),
        GoRoute(
          path: '/inicio',
          builder: (_, _) => const Scaffold(body: Text('Portada del corredor')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [rolRepositoryProvider.overrideWithValue(rol)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('la cuenta administradora entra', (tester) async {
    await abrir(tester, esAdmin: () async => true);

    expect(find.text('Gestión de niveles'), findsOneWidget);
  });

  testWidgets('una cuenta normal no ve la pantalla, ni escribiendo la '
      'dirección a mano', (tester) async {
    await abrir(tester, esAdmin: () async => false);

    expect(find.text('Gestión de niveles'), findsNothing);
    expect(
      find.text('Esta sección es solo para administradores'),
      findsOneWidget,
    );
  });

  testWidgets('desde el aviso se vuelve al inicio', (tester) async {
    await abrir(tester, esAdmin: () async => false);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Volver al inicio'));
    await tester.pumpAndSettle();

    expect(find.text('Portada del corredor'), findsOneWidget);
  });

  testWidgets('si el rol no se puede leer, no entra', (tester) async {
    // Al revés se abriría una gestión que después no podría guardar nada,
    // porque RLS rechazaría la escritura.
    await abrir(tester, esAdmin: () async => throw Exception('sin red'));

    expect(find.text('Gestión de niveles'), findsNothing);
    expect(
      find.text('Esta sección es solo para administradores'),
      findsOneWidget,
    );
  });

  testWidgets('mientras resuelve el rol no enseña la pantalla', (tester) async {
    final pendiente = Completer<bool>();
    await abrir(tester, esAdmin: () => pendiente.future, esperar: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Gestión de niveles'), findsNothing);

    pendiente.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Gestión de niveles'), findsOneWidget);
  });

  testWidgets('el rol se consulta, no se supone', (tester) async {
    await abrir(tester, esAdmin: () async => true);

    expect(rol.consultas, 1);
  });
}
