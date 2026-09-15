import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/models/metricas_salud.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/services/permisos_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/services/salud_service.dart';
import 'package:traza/widgets/seccion_salud.dart';

class _MockPermisosService extends Mock implements PermisosService {}

class _MockSaludService extends Mock implements SaludService {}

class _RepositorioFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Datos de salud en el resumen del entrenamiento (SCRUM-79).
void main() {
  late _MockPermisosService permisos;
  late _MockSaludService salud;

  final fin = DateTime(2026, 9, 15, 7, 30);
  final resumen = ResumenEntrenamiento(
    entrenamientoId: 'e1',
    nombreActividad: 'Correr',
    fechaFin: fin,
    duracion: const Duration(minutes: 30),
  );

  const metricas = MetricasSalud(
    frecuenciaPromedio: 142,
    frecuenciaMaxima: 171,
    calorias: 320,
    pasos: 5230,
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
    ).thenAnswer((_) async => metricas);
  });

  void cuandoSaludEsta(EstadoPermiso estado) {
    when(() => permisos.estadoSalud()).thenAnswer((_) async => estado);
  }

  Future<ProviderContainer> montar(
    WidgetTester tester, {
    ResumenEntrenamiento? de,
  }) async {
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
          home: Scaffold(body: SeccionSalud.deResumen(de ?? resumen)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(SeccionSalud)));
  }

  testWidgets('con permiso muestra los datos del entrenamiento', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.concedido);

    await montar(tester);

    expect(find.text('Datos de salud'), findsOneWidget);
    expect(find.text('142 lpm'), findsOneWidget);
    expect(find.text('171 lpm'), findsOneWidget);
    expect(find.text('320 kcal'), findsOneWidget);
    expect(find.text('5230'), findsOneWidget);
  });

  testWidgets('lee desde el primer punto GPS hasta el final', (tester) async {
    cuandoSaludEsta(EstadoPermiso.concedido);
    final primerPunto = DateTime(2026, 9, 15, 6, 50);

    await montar(
      tester,
      de: ResumenEntrenamiento(
        entrenamientoId: 'e1',
        nombreActividad: 'Correr',
        fechaFin: fin,
        duracion: const Duration(minutes: 30),
        puntos: [
          PuntoGps(latitud: 6.2, longitud: -75.5, capturadoEn: primerPunto),
        ],
      ),
    );

    verify(() => salud.leer(inicio: primerPunto, fin: fin)).called(1);
  });

  testWidgets('sin puntos GPS calcula el inicio con la duración', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.concedido);

    await montar(tester);

    verify(
      () => salud.leer(inicio: DateTime(2026, 9, 15, 7), fin: fin),
    ).called(1);
  });

  testWidgets('sin permiso no lee ni muestra nada', (tester) async {
    cuandoSaludEsta(EstadoPermiso.denegado);

    await montar(tester);

    expect(find.text('Datos de salud'), findsNothing);
    verifyNever(
      () => salud.leer(
        inicio: any(named: 'inicio'),
        fin: any(named: 'fin'),
      ),
    );
  });

  testWidgets('si eligió entrenar sin datos de salud, no los muestra', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.concedido);
    final contenedor = await montar(tester);

    contenedor.read(permisosProvider.notifier).omitirSalud();
    await tester.pumpAndSettle();

    expect(find.text('Datos de salud'), findsNothing);
  });

  testWidgets('si no se registró nada, no ocupa espacio', (tester) async {
    cuandoSaludEsta(EstadoPermiso.concedido);
    when(
      () => salud.leer(
        inicio: any(named: 'inicio'),
        fin: any(named: 'fin'),
      ),
    ).thenAnswer((_) async => const MetricasSalud());

    await montar(tester);

    expect(find.text('Datos de salud'), findsNothing);
  });

  testWidgets('si la lectura falla, el resumen sigue sin la sección', (
    tester,
  ) async {
    cuandoSaludEsta(EstadoPermiso.concedido);
    when(
      () => salud.leer(
        inicio: any(named: 'inicio'),
        fin: any(named: 'fin'),
      ),
    ).thenThrow(Exception('Health Connect'));

    await montar(tester);

    expect(find.text('Datos de salud'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('solo muestra los datos que el reloj registró', (tester) async {
    cuandoSaludEsta(EstadoPermiso.concedido);
    when(
      () => salud.leer(
        inicio: any(named: 'inicio'),
        fin: any(named: 'fin'),
      ),
    ).thenAnswer((_) async => const MetricasSalud(pasos: 3100));

    await montar(tester);

    expect(find.text('3100'), findsOneWidget);
    expect(find.textContaining('lpm'), findsNothing);
  });
}
