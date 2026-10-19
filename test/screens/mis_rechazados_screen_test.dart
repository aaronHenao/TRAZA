import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/moderacion_foro.dart';
import 'package:traza/screens/foro/mis_rechazados_screen.dart';
import 'package:traza/services/cambios_foro.dart';
import 'package:traza/services/foro_service.dart';

import '../utiles/foro_repository_falso.dart';
import '../utiles/fuente_cambios_foro_falsa.dart';

/// Lo que la moderación le rechazó al usuario (SCRUM-322 / SCRUM-339) y sus
/// faltas (SCRUM-338).
void main() {
  late ForoRepositorioFalso repositorio;

  Future<void> abrir(
    WidgetTester tester,
    List<ModeracionForo> moderaciones,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = ForoRepositorioFalso(moderaciones: moderaciones);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          foroRepositoryProvider.overrideWithValue(repositorio),
          usuarioActualProvider.overrideWithValue(() => 'usuario-1'),
          fuenteCambiosForoProvider.overrideWithValue(FuenteCambiosForoFalsa()),
        ],
        child: const MaterialApp(home: MisRechazadosScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('muestra cada rechazo con su motivo, quién y cuándo', (
    tester,
  ) async {
    await abrir(tester, [
      moderacionDePrueba(
        titulo: 'Compra ya',
        fechaDecision: DateTime(2026, 10, 16, 14, 5, 9),
      ),
      moderacionDePrueba(
        id: 'mod-2',
        tipo: TipoModeracion.comentario,
        contenido: 'Grosería',
        motivo: 'Acoso o insultos',
        categorias: const ['Acoso o insultos'],
        responsable: ResponsableModeracion.admin,
        responsableNombre: 'David',
      ),
    ]);

    expect(find.text('Compra ya'), findsOneWidget);
    expect(find.text('Motivo: Spam'), findsOneWidget);
    expect(find.text('Rechazada por: Moderación automática'), findsOneWidget);
    expect(find.text('Fecha: 16 oct 2026, 2:05:09 p. m.'), findsOneWidget);

    expect(find.text('Grosería'), findsOneWidget);
    expect(find.text('Infracción: Acoso o insultos'), findsOneWidget);
    // Al autor no se le dice qué administrador fue.
    expect(find.text('Rechazada por: Administrador'), findsOneWidget);
    expect(find.textContaining('David'), findsNothing);
  });

  testWidgets('dice cuántas faltas lleva', (tester) async {
    await abrir(tester, [
      moderacionDePrueba(id: 'a'),
      moderacionDePrueba(id: 'b'),
    ]);

    expect(find.text(MisRechazadosScreen.textoFaltas(2)), findsOneWidget);
  });

  testWidgets('lo que todavía espera no aparece, ni la duda de la IA', (
    tester,
  ) async {
    await abrir(tester, [
      moderacionDePrueba(
        estado: EstadoModeracion.pendiente,
        titulo: 'Dudosa',
        motivo: 'La IA no está segura: spam',
      ),
    ]);

    expect(find.text('Dudosa'), findsNothing);
    expect(find.textContaining('no está segura'), findsNothing);
    expect(find.text('No tienes nada rechazado'), findsOneWidget);
  });

  testWidgets('al abrirla marca los rechazos como vistos', (tester) async {
    await abrir(tester, [moderacionDePrueba()]);

    expect(repositorio.rechazosMarcados, 1);
    expect(repositorio.moderacionesGuardadas.single.vistaPorAutor, isTrue);
  });
}
