import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/rol_ganado.dart';
import 'package:traza/models/runner_experto.dart';
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

  testWidgets('dice qué funcionalidades le habilita el rol', (tester) async {
    // Las mismas que explica la pantalla del rol (SCRUM-213): una sola lista
    // para las dos, así no se contradicen.
    await entrarALaApp(tester, RolesFalso.experto());

    for (final ventaja in VentajaRunnerExperto.values) {
      expect(find.text(ventaja.titulo), findsOneWidget);
    }
  });

  testWidgets('al entrar le pide a la base revisar la cuenta', (tester) async {
    // La antigüedad se cumple sola con el tiempo: sin esta revisión, quien ya
    // tuviera la XP no recibiría el rol hasta su siguiente entrenamiento.
    await entrarALaApp(tester, RolesFalso());

    expect(repositorio.evaluaciones, 1);
  });
}
