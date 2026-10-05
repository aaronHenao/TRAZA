import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/rol_ganado.dart';
import 'package:traza/services/roles_service.dart';
import 'package:traza/widgets/ventana_rol_experto.dart';

import '../utiles/roles_falso.dart';

/// Pruebas del anuncio del rol desbloqueado (SCRUM-229).
void main() {
  late RolesFalso repositorio;

  Future<void> entrarALaApp(WidgetTester tester, RolesFalso roles) async {
    repositorio = roles;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rolesRepositoryProvider.overrideWithValue(repositorio)],
        child: const MaterialApp(
          home: AvisoRolNuevo(hijo: Scaffold(body: Text('Portada'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('al entrar, avisa del rol recién desbloqueado', (tester) async {
    await entrarALaApp(tester, RolesFalso.experto());

    expect(find.text('¡Desbloqueaste Runner Experto!'), findsOneWidget);
    // La portada sigue detrás: el aviso no reemplaza la pantalla.
    expect(find.text('Portada'), findsOneWidget);
  });

  testWidgets('al cerrarlo queda marcado como anunciado', (tester) async {
    await entrarALaApp(tester, RolesFalso.experto());

    await tester.tap(find.byKey(VentanaRolExperto.claveCerrar));
    await tester.pumpAndSettle();

    expect(repositorio.anunciados, [RolGanable.experto]);
    expect(find.text('¡Desbloqueaste Runner Experto!'), findsNothing);
  });

  testWidgets('un rol ya anunciado no se vuelve a avisar', (tester) async {
    // Criterio 5: volver a cumplir la condición no reabre el aviso.
    await entrarALaApp(
      tester,
      RolesFalso.experto(anunciadoEn: DateTime.utc(2026, 10, 3, 9)),
    );

    expect(find.text('¡Desbloqueaste Runner Experto!'), findsNothing);
    expect(repositorio.anunciados, isEmpty);
  });

  testWidgets('sin roles desbloqueados no muestra nada', (tester) async {
    await entrarALaApp(tester, RolesFalso());

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Portada'), findsOneWidget);
  });

  testWidgets('si los roles no se pueden leer, la portada se abre igual', (
    tester,
  ) async {
    // El aviso es un extra: un fallo de red no puede dejar al corredor sin su
    // portada.
    await entrarALaApp(tester, RolesFalso()..error = StateError('sin red'));

    expect(find.text('Portada'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('mientras no se definan, no promete funcionalidades', (
    tester,
  ) async {
    // La lista la define SCRUM-210; hasta entonces la ventana anuncia el rol
    // sin inventar qué habilita.
    await entrarALaApp(tester, RolesFalso.experto());

    expect(beneficiosRunnerExperto, isEmpty);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });
}
