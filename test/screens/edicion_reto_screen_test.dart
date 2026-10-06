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
  _RetosFalso({this.enCurso = 0, this.llevaMax = 0});

  /// Cuántos corredores tienen el reto en curso.
  final int enCurso;

  /// Los km del que va más adelantado.
  final double llevaMax;

  CambiosReto? recibido;

  @override
  Future<ProgresoEnCurso> progresoEnCurso(Reto reto) async =>
      (corredores: enCurso, maximoKm: llevaMax);

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

  Future<void> abrir(
    WidgetTester tester,
    Reto original, {
    int enCurso = 0,
    double llevaMax = 0,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = _RetosFalso(enCurso: enCurso, llevaMax: llevaMax);
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

  group(
    'avisar antes de cambiar lo que la gente esta haciendo (criterio 2)',
    () {
      Future<void> cambiarMeta(WidgetTester tester, String nueva) async {
        await tester.enterText(find.widgetWithText(TextField, '15'), nueva);
        await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
        await tester.pumpAndSettle();
      }

      testWidgets('con gente en curso, cambiar la meta pregunta antes', (
        tester,
      ) async {
        await abrir(tester, reto(), enCurso: 3);

        await cambiarMeta(tester, '20');

        expect(find.text('Hay gente haciendo este reto'), findsOneWidget);
        expect(find.text('3 corredores lo tienen en curso.'), findsOneWidget);
        // Todavia no se ha guardado nada.
        expect(repositorio.recibido, isNull);
      });

      testWidgets('dice que cambia exactamente, no un aviso generico', (
        tester,
      ) async {
        await abrir(tester, reto(), enCurso: 2);

        await cambiarMeta(tester, '20');

        expect(
          find.text(
            'La meta pasa de 15 a 20 km, con el progreso que ya llevan.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('con un solo corredor lo dice en singular', (tester) async {
        await abrir(tester, reto(), enCurso: 1);

        await cambiarMeta(tester, '20');

        expect(find.text('1 corredor lo tiene en curso.'), findsOneWidget);
      });

      testWidgets('confirmar guarda los cambios', (tester) async {
        await abrir(tester, reto(), enCurso: 3);
        await cambiarMeta(tester, '20');

        await tester.tap(find.byKey(FormularioRetoScreen.claveConfirmar));
        await tester.pumpAndSettle();

        expect(repositorio.recibido?.metaKm, 20);
      });

      testWidgets('cancelar no guarda y deja lo escrito', (tester) async {
        await abrir(tester, reto(), enCurso: 3);
        await cambiarMeta(tester, '20');

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(repositorio.recibido, isNull);
        // Se vuelve al formulario con el cambio puesto: cancelar es "ahora no",
        // no "descarta lo que escribi".
        expect(find.text('Editar reto'), findsOneWidget);
        expect(find.widgetWithText(TextField, '20'), findsOneWidget);
      });

      testWidgets('la XP tambien avisa', (tester) async {
        await abrir(tester, reto(), enCurso: 2);

        await tester.enterText(find.widgetWithText(TextField, '200'), '100');
        await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
        await tester.pumpAndSettle();

        expect(find.text('La XP pasa de 200 a 100.'), findsOneWidget);
      });

      testWidgets('extender el plazo tambien avisa', (tester) async {
        await abrir(tester, reto(), enCurso: 2);

        await tester.tap(find.byKey(FormularioRetoScreen.claveExtender));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
        await tester.pumpAndSettle();

        expect(find.text('El plazo se alarga un día.'), findsOneWidget);
      });

      testWidgets('sin nadie en curso se guarda sin preguntar', (tester) async {
        await abrir(tester, reto());

        await cambiarMeta(tester, '20');

        expect(find.text('Hay gente haciendo este reto'), findsNothing);
        expect(repositorio.recibido?.metaKm, 20);
      });

      testWidgets('corregir solo el nombre no pregunta aunque haya gente', (
        tester,
      ) async {
        // Lo que no cambia lo que hay que hacer ni lo que se gana no merece
        // interrumpir al administrador.
        await abrir(tester, reto(), enCurso: 5);

        await tester.enterText(
          find.widgetWithText(TextField, 'Corre 15 km esta semana'),
          'Corre 15 km (corregido)',
        );
        await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
        await tester.pumpAndSettle();

        expect(find.text('Hay gente haciendo este reto'), findsNothing);
        expect(repositorio.recibido?.nombre, 'Corre 15 km (corregido)');
      });

      testWidgets('con datos invalidos se marcan los campos, no se pregunta', (
        tester,
      ) async {
        await abrir(tester, reto(), enCurso: 3);

        await cambiarMeta(tester, '0');

        expect(find.text('Hay gente haciendo este reto'), findsNothing);
        expect(find.text('La meta debe ser mayor que cero.'), findsOneWidget);
      });
    },
  );

  group('la meta no baja de lo que alguien ya corrio', () {
    Future<void> cambiarMeta(WidgetTester tester, String nueva) async {
      await tester.enterText(find.widgetWithText(TextField, '15'), nueva);
      await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
      await tester.pumpAndSettle();
    }

    testWidgets('al abrir ya dice cuanto lleva el mas adelantado', (
      tester,
    ) async {
      // Antes de escribir nada: el dato que hace falta para elegir la meta,
      // no un regano por haberla escrito mal (lleva 10 de 15).
      await abrir(tester, reto(), enCurso: 2, llevaMax: 10);

      expect(
        find.text('El que va más adelantado lleva 10 km.'),
        findsOneWidget,
      );
    });

    testWidgets('sin nadie en curso no habla de progreso ajeno', (
      tester,
    ) async {
      await abrir(tester, reto());

      expect(find.textContaining('más adelantado'), findsNothing);
    });

    testWidgets('bajarla por debajo de lo corrido no se guarda', (
      tester,
    ) async {
      await abrir(tester, reto(), enCurso: 1, llevaMax: 10);

      await cambiarMeta(tester, '9');

      expect(
        find.text(
          'Un corredor ya lleva 10 km. La meta no puede bajar de ahí: lo '
          'dejaría sin poder completarlo.',
        ),
        findsOneWidget,
      );
      // Ni se pregunta ni se guarda: no es una decision del administrador,
      // es un dato que no se puede sostener.
      expect(find.text('Hay gente haciendo este reto'), findsNothing);
      expect(repositorio.recibido, isNull);
    });

    testWidgets('puede quedar justo en lo que lleva el mas adelantado', (
      tester,
    ) async {
      await abrir(tester, reto(), enCurso: 1, llevaMax: 10);

      await cambiarMeta(tester, '10');
      await tester.tap(find.byKey(FormularioRetoScreen.claveConfirmar));
      await tester.pumpAndSettle();

      // Con 10 de 10 el reto se cierra en su proxima carrera, que es el
      // comportamiento normal de cualquier reto cumplido.
      expect(repositorio.recibido?.metaKm, 10);
    });

    testWidgets('bajarla sin dejar a nadie atras sigue siendo posible', (
      tester,
    ) async {
      await abrir(tester, reto(), enCurso: 1, llevaMax: 10);

      await cambiarMeta(tester, '12');
      await tester.tap(find.byKey(FormularioRetoScreen.claveConfirmar));
      await tester.pumpAndSettle();

      expect(repositorio.recibido?.metaKm, 12);
    });

    testWidgets('subirla no mira lo que lleve nadie', (tester) async {
      await abrir(tester, reto(), enCurso: 1, llevaMax: 10);

      await cambiarMeta(tester, '20');
      await tester.tap(find.byKey(FormularioRetoScreen.claveConfirmar));
      await tester.pumpAndSettle();

      expect(repositorio.recibido?.metaKm, 20);
    });

    testWidgets('corregido el numero, el campo deja de estar en rojo', (
      tester,
    ) async {
      await abrir(tester, reto(), enCurso: 1, llevaMax: 10);
      await cambiarMeta(tester, '9');

      await tester.enterText(find.widgetWithText(TextField, '9'), '11');
      await tester.pump();

      expect(find.textContaining('no puede bajar de ahí'), findsNothing);
    });
  });
}
