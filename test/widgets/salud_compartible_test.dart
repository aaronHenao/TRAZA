import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/metricas_salud.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/salud_service.dart';
import 'package:traza/widgets/salud_compartible.dart';

class _MockPermisosService extends Mock implements PermisosService {}

class _MockSaludService extends Mock implements SaludService {}

class _RepositorioFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Datos de salud en la foto para compartir (SCRUM-84).
void main() {
  late _MockPermisosService permisos;
  late _MockSaludService salud;

  final ventana = (
    inicio: DateTime(2026, 9, 15, 7),
    fin: DateTime(2026, 9, 15, 7, 30),
  );

  setUp(() {
    permisos = _MockPermisosService();
    salud = _MockSaludService();
    when(
      () => permisos.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
    when(
      () => salud.leer(
        inicio: any(named: 'inicio'),
        fin: any(named: 'fin'),
      ),
    ).thenAnswer(
      (_) async => const MetricasSalud(
        frecuenciaPromedio: 142,
        frecuenciaMaxima: 171,
        calorias: 320,
        pasos: 5230,
      ),
    );
  });

  Future<void> montar(WidgetTester tester, EstadoPermiso estadoSalud) async {
    when(() => permisos.estadoSalud()).thenAnswer((_) async => estadoSalud);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permisosServiceProvider.overrideWithValue(permisos),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _RepositorioFalso(),
          ),
          saludServiceProvider.overrideWithValue(salud),
        ],
        child: MaterialApp(
          home: Scaffold(body: SaludCompartible(ventana: ventana)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('con permiso escribe los datos en la foto', (tester) async {
    await montar(tester, EstadoPermiso.concedido);

    expect(find.text('142 lpm'), findsOneWidget);
    expect(find.text('320 kcal'), findsOneWidget);
    expect(find.text('5230 pasos'), findsOneWidget);
  });

  testWidgets('sin permiso la foto sale sin datos de salud', (tester) async {
    await montar(tester, EstadoPermiso.denegado);

    expect(find.textContaining('lpm'), findsNothing);
    expect(find.textContaining('kcal'), findsNothing);
    expect(find.textContaining('pasos'), findsNothing);
  });

  test('solo escribe los datos que se registraron', () {
    final textos = SaludCompartible.textosPara(
      const MetricasSalud(calorias: 150),
    );

    expect(textos.map((t) => t.$2), ['150 kcal']);
  });
}
