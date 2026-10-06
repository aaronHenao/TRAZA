import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/screens/admin/formulario_reto_screen.dart';
import 'package:traza/services/actividad_provider.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';

import '../utiles/retos_repository_falso.dart';

class _RetosFalso extends RetosRepositorioFalso {
  CambiosReto? recibido;

  @override
  Future<Reto> editar(Reto original, CambiosReto cambios) async {
    recibido = cambios;
    return Reto(
      id: original.id,
      nombre: cambios.nombre,
      descripcion: cambios.descripcion,
      periodicidad: original.periodicidad,
      metaKm: cambios.metaKm,
      xpOtorgada: cambios.xpOtorgada,
      vigencia: cambios.vigencia,
      estado: original.estado,
      tipoActividad: original.tipoActividad,
    );
  }
}

/// El formulario en modo edición (SCRUM-149).
void main() {
  final ahora = DateTime(2026, 10, 5, 9);

  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');
  const tipos = [
    correr,
    TipoActividad(id: 'tipo-trote', nombre: 'Trote'),
    TipoActividad(id: 'tipo-caminar', nombre: 'Caminar'),
  ];

  Reto reto({
    PeriodicidadReto periodicidad = PeriodicidadReto.semanal,
    DateTime? inicio,
    DateTime? fin,
  }) => Reto(
    id: 'r1',
    nombre: 'Corre 15 km esta semana',
    descripcion: 'Suma 15 km entre lunes y domingo.',
    periodicidad: periodicidad,
    metaKm: 15,
    xpOtorgada: 200,
    vigencia: VigenciaReto(
      inicio: inicio ?? DateTime(2026, 10, 5),
      fin: fin ?? DateTime(2026, 10, 11),
    ),
    estado: EstadoReto.activo,
    tipoActividad: correr,
  );

  late _RetosFalso repositorio;

  Future<void> abrir(WidgetTester tester, Reto original) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = _RetosFalso();
    // Con una pantalla detrás, como en la app: el formulario vuelve a ella
    // al guardar.
    final router = GoRouter(
      initialLocation: '/admin/retos/editar',
      routes: [
        GoRoute(
          path: '/admin/retos',
          builder: (_, _) => const Scaffold(body: Text('Gestión de retos')),
          routes: [
            GoRoute(
              path: 'editar',
              builder: (_, _) => FormularioRetoScreen(original: original),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retosRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => ahora),
          tiposActividadProvider.overrideWith((ref) async => tipos),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('el formulario llega lleno', () {
    testWidgets('con los datos del reto y su propio título', (tester) async {
      await abrir(tester, reto());

      expect(find.text('Editar reto'), findsOneWidget);
      expect(find.text('Corre 15 km esta semana'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
    });

    testWidgets('sin tocar nada se puede guardar', (tester) async {
      await abrir(tester, reto());

      await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
      await tester.pumpAndSettle();

      expect(repositorio.recibido?.nombre, 'Corre 15 km esta semana');
    });
  });

  group('lo que no se cambia', () {
    testWidgets('la periodicidad se ve, y solo la suya', (tester) async {
      await abrir(tester, reto());

      expect(find.text('Semanal'), findsOneWidget);
      // Las otras no se pintan: botones que no responden parecen una pantalla
      // rota.
      expect(find.text('Diario'), findsNothing);
      expect(find.text('Mensual'), findsNothing);
    });

    testWidgets('el tipo de actividad, igual', (tester) async {
      await abrir(tester, reto());

      expect(find.text('Correr'), findsOneWidget);
      expect(find.text('Trote'), findsNothing);
      expect(find.text('Caminar'), findsNothing);
    });

    testWidgets('se dice por qué no responden', (tester) async {
      await abrir(tester, reto());

      expect(find.text('· No se cambia'), findsNWidgets(2));
    });
  });

  group('extender el plazo', () {
    testWidgets('el botón abre el calendario', (tester) async {
      // Lo que falló al probarlo a mano: showDatePicker exige que el día en
      // el que abre caiga dentro del rango, y el final actual queda justo
      // fuera. El calendario no llegaba a aparecer y el botón no hacía nada.
      await abrir(tester, reto());

      await tester.tap(find.byKey(FormularioRetoScreen.claveExtender));
      await tester.pumpAndSettle();

      expect(find.text('Hasta cuándo dura el reto'), findsOneWidget);
    });

    testWidgets('también en un reto mensual', (tester) async {
      await abrir(
        tester,
        reto(
          periodicidad: PeriodicidadReto.mensual,
          inicio: DateTime(2026, 10),
          fin: DateTime(2026, 10, 31),
        ),
      );

      await tester.tap(find.byKey(FormularioRetoScreen.claveExtender));
      await tester.pumpAndSettle();

      expect(find.text('Hasta cuándo dura el reto'), findsOneWidget);
    });

    testWidgets('el calendario abre en el primer día que se puede elegir', (
      tester,
    ) async {
      await abrir(tester, reto());

      await tester.tap(find.byKey(FormularioRetoScreen.claveExtender));
      await tester.pumpAndSettle();

      // El reto termina el 11, así que el calendario abre en el 12 y
      // aceptar sin elegir otro día deja esa fecha.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Del 5 de octubre al 12 de octubre'), findsOneWidget);
    });

    testWidgets('lo elegido se guarda', (tester) async {
      await abrir(tester, reto());

      await tester.tap(find.byKey(FormularioRetoScreen.claveExtender));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
      await tester.pumpAndSettle();

      expect(repositorio.recibido!.vigencia.fin, DateTime(2026, 10, 12));
      // El inicio nunca se mueve.
      expect(repositorio.recibido!.vigencia.inicio, DateTime(2026, 10, 5));
    });

    testWidgets('mientras no se extienda, lo dice', (tester) async {
      await abrir(tester, reto());

      expect(find.text('El plazo solo se puede alargar.'), findsOneWidget);
      expect(find.text('Extender el plazo'), findsOneWidget);
    });
  });

  group('validaciones al editar (criterio 3)', () {
    testWidgets('sin nombre se marca y no se guarda', (tester) async {
      await abrir(tester, reto());

      await tester.enterText(
        find.widgetWithText(TextField, 'Corre 15 km esta semana'),
        '   ',
      );
      await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
      await tester.pumpAndSettle();

      expect(find.text('Ponle un nombre al reto.'), findsOneWidget);
      expect(repositorio.recibido, isNull);
    });

    testWidgets('una meta de cero tampoco', (tester) async {
      await abrir(tester, reto());

      await tester.enterText(find.widgetWithText(TextField, '15'), '0');
      await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
      await tester.pumpAndSettle();

      expect(find.text('La meta debe ser mayor que cero.'), findsOneWidget);
      expect(repositorio.recibido, isNull);
    });
  });
}
