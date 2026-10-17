import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/services/permisos_provider.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/widgets/ventana_permiso_salud.dart';

class _MockPermisosService extends Mock implements PermisosService {}

class _RepositorioFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas de la ventana que ofrece el permiso de salud antes de iniciar
/// (SCRUM-131, criterio 3).
void main() {
  late _MockPermisosService servicio;
  late ProviderContainer container;

  /// Lo que devolvió la última llamada a `ofrecerPermisoSalud`, o null si
  /// todavía no terminó.
  bool? puedeIniciar;

  setUp(() {
    servicio = _MockPermisosService();
    puedeIniciar = null;
    when(
      () => servicio.estadoUbicacion(),
    ).thenAnswer((_) async => EstadoPermiso.concedido);
  });

  void saludEsta(EstadoPermiso estado) {
    when(() => servicio.estadoSalud()).thenAnswer((_) async => estado);
  }

  void alPedirSaludResponde(EstadoPermiso estado) {
    when(() => servicio.solicitarSalud()).thenAnswer((_) async => estado);
  }

  Future<void> montar(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [
        permisosServiceProvider.overrideWithValue(servicio),
        permisosUsuarioRepositoryProvider.overrideWithValue(
          _RepositorioFalso(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: _PantallaDeInicio(
            alTerminar: (resultado) => puedeIniciar = resultado,
          ),
        ),
      ),
    );
  }

  /// Toca "Iniciar", como haría el usuario antes de empezar.
  Future<void> iniciar(WidgetTester tester) async {
    puedeIniciar = null;
    await tester.tap(find.text('Iniciar'));
    await tester.pumpAndSettle();
  }

  bool hayVentana() =>
      find.text(VentanaPermisoSalud.titulo).evaluate().isNotEmpty;

  testWidgets('con el permiso concedido deja iniciar sin preguntar', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.concedido);
    await montar(tester);

    await iniciar(tester);

    expect(hayVentana(), isFalse);
    expect(puedeIniciar, isTrue);
  });

  testWidgets('sin Health Connect no pregunta: no hay de dónde leer', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.noDisponible);
    await montar(tester);

    await iniciar(tester);

    expect(hayVentana(), isFalse);
    expect(puedeIniciar, isTrue);
  });

  testWidgets('sin el permiso muestra la ventana antes de iniciar', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.denegado);
    await montar(tester);

    await iniciar(tester);

    expect(hayVentana(), isTrue);
    expect(find.text(VentanaPermisoSalud.aceptar), findsOneWidget);
    expect(find.text(VentanaPermisoSalud.continuarSin), findsOneWidget);
    // Todavía no se decide nada: se espera la respuesta del usuario.
    expect(puedeIniciar, isNull);
  });

  testWidgets('en iOS, que nunca dice si se concedió, también la ofrece', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.desconocido);
    await montar(tester);

    await iniciar(tester);

    expect(hayVentana(), isTrue);
  });

  testWidgets('"Aceptar" pide el permiso y, si lo concede, usa sus datos', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.denegado);
    alPedirSaludResponde(EstadoPermiso.concedido);
    await montar(tester);
    await iniciar(tester);

    await tester.tap(find.text(VentanaPermisoSalud.aceptar));
    await tester.pumpAndSettle();

    verify(() => servicio.solicitarSalud()).called(1);
    expect(hayVentana(), isFalse);
    expect(puedeIniciar, isTrue);
    final permisos = container.read(permisosProvider);
    expect(permisos.salud, EstadoPermiso.concedido);
    expect(permisos.saludOmitida, isFalse);
  });

  testWidgets('si lo niega, deja iniciar igual sin datos de salud', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.denegado);
    alPedirSaludResponde(EstadoPermiso.denegado);
    await montar(tester);
    await iniciar(tester);

    await tester.tap(find.text(VentanaPermisoSalud.aceptar));
    await tester.pumpAndSettle();

    expect(puedeIniciar, isTrue);
    expect(container.read(permisosProvider).saludOmitida, isTrue);
  });

  testWidgets('"Continuar sin datos de salud" deja iniciar sin pedirlo', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.denegado);
    await montar(tester);
    await iniciar(tester);

    await tester.tap(find.text(VentanaPermisoSalud.continuarSin));
    await tester.pumpAndSettle();

    verifyNever(() => servicio.solicitarSalud());
    expect(hayVentana(), isFalse);
    expect(puedeIniciar, isTrue);
    expect(container.read(permisosProvider).saludOmitida, isTrue);
  });

  testWidgets('la vuelve a ofrecer en cada inicio mientras falte', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.denegado);
    await montar(tester);
    await iniciar(tester);
    await tester.tap(find.text(VentanaPermisoSalud.continuarSin));
    await tester.pumpAndSettle();

    await iniciar(tester);

    expect(hayVentana(), isTrue);
  });

  testWidgets('cerrarla con "atrás" no deja iniciar', (tester) async {
    saludEsta(EstadoPermiso.denegado);
    await montar(tester);
    await iniciar(tester);

    Navigator.of(tester.element(find.byType(VentanaPermisoSalud))).pop();
    await tester.pumpAndSettle();

    verifyNever(() => servicio.solicitarSalud());
    expect(puedeIniciar, isFalse);
  });

  testWidgets('un toque fuera de la ventana no decide por el usuario', (
    tester,
  ) async {
    saludEsta(EstadoPermiso.denegado);
    await montar(tester);
    await iniciar(tester);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(hayVentana(), isTrue);
    expect(puedeIniciar, isNull);
  });
}

/// Un botón que llama a `ofrecerPermisoSalud`, como hacen las pantallas que
/// arrancan una actividad.
class _PantallaDeInicio extends ConsumerWidget {
  const _PantallaDeInicio({required this.alTerminar});

  final void Function(bool puedeIniciar) alTerminar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async =>
              alTerminar(await ofrecerPermisoSalud(context, ref)),
          child: const Text('Iniciar'),
        ),
      ),
    );
  }
}
