import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:traza/models/estado_permisos.dart';
import 'package:traza/services/permisos_service.dart';
import 'package:traza/services/permisos_usuario_service.dart';
import 'package:traza/widgets/aviso_permiso_ubicacion.dart';

class _MockPermisosService extends Mock implements PermisosService {}

/// Lo que la app guarda en `permisos_usuario`: aquí no interesa.
class _PermisosGuardadosFalso implements PermisosUsuarioRepository {
  @override
  Future<void> guardar(TipoPermiso tipo, {required bool concedido}) async {}
}

/// Pruebas del aviso que pide la ubicación (SCRUM-248 y SCRUM-290).
void main() {
  late _MockPermisosService permisos;

  setUp(() {
    permisos = _MockPermisosService();
    when(
      () => permisos.estadoSalud(),
    ).thenAnswer((_) async => EstadoPermiso.desconocido);
    when(() => permisos.abrirAjustes()).thenAnswer((_) async {});
  });

  Future<void> montar(
    WidgetTester tester,
    EstadoPermiso ubicacion, {
    bool mostrar = true,
    bool enNavegador = false,
  }) async {
    when(() => permisos.estadoUbicacion()).thenAnswer((_) async => ubicacion);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permisosServiceProvider.overrideWithValue(permisos),
          permisosUsuarioRepositoryProvider.overrideWithValue(
            _PermisosGuardadosFalso(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: mostrar
                ? AvisoPermisoUbicacion(enNavegador: enNavegador)
                : const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// El usuario sale a los ajustes del teléfono y vuelve a la app. Pasa por
  /// cada estado intermedio, como lo hace el sistema.
  Future<void> irYVolverDeLosAjustes(WidgetTester tester) async {
    for (final estado in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(estado);
    }
    await tester.pumpAndSettle();
  }

  FilledButton boton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(AvisoPermisoUbicacion.claveBoton));

  group('sin el permiso', () {
    testWidgets('explica para qué hace falta y ofrece concederlo', (
      tester,
    ) async {
      await montar(tester, EstadoPermiso.denegado);

      expect(find.text(AvisoPermisoUbicacion.titulo), findsOneWidget);
      expect(find.text(AvisoPermisoUbicacion.porQue), findsOneWidget);
      expect(find.text('Aceptar'), findsOneWidget);
    });

    testWidgets('"Aceptar" se lo pide al sistema', (tester) async {
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await montar(tester, EstadoPermiso.denegado);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      verify(() => permisos.solicitarUbicacion()).called(1);
      verifyNever(() => permisos.abrirAjustes());
    });

    testWidgets('mientras la ventana del sistema está abierta no se puede '
        'pedir otra vez', (tester) async {
      final respuesta = Completer<EstadoPermiso>();
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) => respuesta.future);
      await montar(tester, EstadoPermiso.denegado);

      await tester.tap(find.text('Aceptar'));
      await tester.pump();

      expect(boton(tester).onPressed, isNull);

      respuesta.complete(EstadoPermiso.denegado);
      await tester.pumpAndSettle();

      // Lo negó: se le puede volver a ofrecer.
      expect(boton(tester).onPressed, isNotNull);
    });
  });

  group('con el permiso bloqueado', () {
    testWidgets('dice cómo activarlo y el botón lo dice también', (
      tester,
    ) async {
      await montar(tester, EstadoPermiso.bloqueado);

      expect(find.text(AvisoPermisoUbicacion.comoActivarlo), findsOneWidget);
      // El sistema ya no muestra su ventana: el botón no promete "Aceptar"
      // cuando lo que hace es salir a los ajustes.
      expect(find.text('Abrir ajustes'), findsOneWidget);
      expect(find.text('Aceptar'), findsNothing);
    });

    testWidgets('"Abrir ajustes" abre los ajustes y no pide nada', (
      tester,
    ) async {
      await montar(tester, EstadoPermiso.bloqueado);

      await tester.tap(find.text('Abrir ajustes'));
      await tester.pumpAndSettle();

      verify(() => permisos.abrirAjustes()).called(1);
      verifyNever(() => permisos.solicitarUbicacion());
    });
  });

  group('en el navegador', () {
    testWidgets('bloqueado, dice cómo activarla en el navegador, no en el '
        'teléfono', (tester) async {
      await montar(tester, EstadoPermiso.bloqueado, enNavegador: true);

      expect(
        find.text(AvisoPermisoUbicacion.comoActivarloEnNavegador),
        findsOneWidget,
      );
      expect(find.text(AvisoPermisoUbicacion.comoActivarlo), findsNothing);
      expect(find.text('Abrir ajustes'), findsNothing);
      expect(find.text('Revisar de nuevo'), findsOneWidget);
    });

    testWidgets('"Revisar de nuevo" vuelve a consultar y no intenta abrir '
        'ajustes', (tester) async {
      // En la web abrir los ajustes no existe: pedirlo lanzaría un error.
      await montar(tester, EstadoPermiso.bloqueado, enNavegador: true);
      clearInteractions(permisos);

      await tester.tap(find.text('Revisar de nuevo'));
      await tester.pumpAndSettle();

      verify(() => permisos.estadoUbicacion()).called(1);
      verifyNever(() => permisos.abrirAjustes());
    });

    testWidgets('si de verdad la activó, el aviso lo nota', (tester) async {
      await montar(tester, EstadoPermiso.bloqueado, enNavegador: true);

      // La activó junto a la dirección de la página.
      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await tester.tap(find.text('Revisar de nuevo'));
      await tester.pumpAndSettle();

      // Con el permiso dado ya no hay nada que activar: el aviso vuelve al
      // texto de siempre, y quien lo muestra deja de mostrarlo.
      expect(
        find.text(AvisoPermisoUbicacion.comoActivarloEnNavegador),
        findsNothing,
      );
    });

    testWidgets('si sigue bloqueada, lo dice: el toque no se pierde sin '
        'respuesta', (tester) async {
      // Tocó "No permitir nunca" y no la ha activado junto a la dirección.
      await montar(tester, EstadoPermiso.bloqueado, enNavegador: true);

      await tester.tap(find.text('Revisar de nuevo'));
      await tester.pumpAndSettle();

      expect(
        find.text(AvisoPermisoUbicacion.sigueBloqueadaEnNavegador),
        findsOneWidget,
      );
    });

    testWidgets('si ya la activó, no dice que sigue bloqueada', (tester) async {
      await montar(tester, EstadoPermiso.bloqueado, enNavegador: true);

      when(
        () => permisos.estadoUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await tester.tap(find.text('Revisar de nuevo'));
      await tester.pumpAndSettle();

      expect(
        find.text(AvisoPermisoUbicacion.sigueBloqueadaEnNavegador),
        findsNothing,
      );
    });

    testWidgets('sin bloquear, "Aceptar" pide el permiso igual que en el '
        'teléfono', (tester) async {
      // El navegador sí muestra su ventanita la primera vez.
      when(
        () => permisos.solicitarUbicacion(),
      ).thenAnswer((_) async => EstadoPermiso.concedido);
      await montar(tester, EstadoPermiso.denegado, enNavegador: true);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      verify(() => permisos.solicitarUbicacion()).called(1);
    });
  });

  group('al volver de los ajustes', () {
    testWidgets('vuelve a consultar el permiso, por si lo concedió allá', (
      tester,
    ) async {
      await montar(tester, EstadoPermiso.bloqueado);
      clearInteractions(permisos);

      await irYVolverDeLosAjustes(tester);

      verify(() => permisos.estadoUbicacion()).called(1);
    });

    testWidgets('sin el aviso en pantalla, no se queda escuchando', (
      tester,
    ) async {
      await montar(tester, EstadoPermiso.bloqueado);
      // El aviso se va —por ejemplo, porque el permiso ya está— y con él
      // su escucha.
      await montar(tester, EstadoPermiso.bloqueado, mostrar: false);
      clearInteractions(permisos);

      await irYVolverDeLosAjustes(tester);

      verifyNever(() => permisos.estadoUbicacion());
    });
  });
}
