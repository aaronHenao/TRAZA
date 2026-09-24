import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/screens/admin/formulario_reto_screen.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_provider.dart';
import 'package:traza/services/retos_service.dart';

/// Repositorio de mentira: anota lo que le mandan y responde lo que la prueba
/// le indique.
class _RetosFalso implements RetosRepository {
  Object? error;
  NuevoReto? recibido;

  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async =>
      const [];

  @override
  Future<Reto> crear(NuevoReto reto) async {
    recibido = reto;
    final error = this.error;
    if (error != null) throw error;

    return Reto(
      id: 'reto-1',
      nombre: reto.nombre,
      descripcion: reto.descripcion,
      periodicidad: reto.periodicidad,
      metaKm: reto.metaKm,
      xpOtorgada: reto.xpOtorgada,
      vigencia: reto.vigencia,
      estado: EstadoReto.activo,
    );
  }
}

/// Pruebas del formulario de creación (SCRUM-139) y de sus validaciones
/// (SCRUM-144).
void main() {
  // Miércoles 23 de septiembre de 2026.
  final ahora = DateTime(2026, 9, 23, 11, 30);

  late _RetosFalso repositorio;

  Future<void> abrirFormulario(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = _RetosFalso();
    final router = GoRouter(
      initialLocation: '/admin/retos',
      routes: [
        GoRoute(
          path: '/admin/retos',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/admin/retos/nuevo'),
              child: const Text('Gestión'),
            ),
          ),
        ),
        GoRoute(
          path: '/admin/retos/nuevo',
          builder: (_, _) => const FormularioRetoScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retosRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Gestión'));
    await tester.pumpAndSettle();
  }

  Future<void> llenar(
    WidgetTester tester, {
    String nombre = 'Corre 5 km hoy',
    String descripcion = 'Una sola sesión de carrera.',
    PeriodicidadReto? periodicidad = PeriodicidadReto.diaria,
    String meta = '5',
    String xp = '50',
  }) async {
    await tester.enterText(find.widgetWithText(TextField, 'Corre 5 km hoy').first, nombre);
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText?.startsWith('Qué tiene') == true,
      ),
      descripcion,
    );
    if (periodicidad != null) {
      await tester.tap(find.text(periodicidad.etiqueta));
      await tester.pump();
    }
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'km',
      ),
      meta,
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.suffixText == 'XP',
      ),
      xp,
    );
    await tester.pump();
  }

  Future<void> tocarCrear(WidgetTester tester) async {
    await tester.tap(find.byKey(FormularioRetoScreen.claveGuardar));
    await tester.pumpAndSettle();
  }

  group('validaciones (SCRUM-144)', () {
    testWidgets('el formulario vacío señala los cinco campos', (tester) async {
      await abrirFormulario(tester);

      await tocarCrear(tester);

      expect(find.text('Ponle un nombre al reto.'), findsOneWidget);
      expect(find.text('Explica qué hay que hacer para cumplirlo.'), findsOneWidget);
      expect(find.text('Elige cada cuánto se renueva.'), findsOneWidget);
      expect(find.text('Indica la meta en kilómetros.'), findsOneWidget);
      expect(find.text('Indica cuánta XP otorga.'), findsOneWidget);
      // Lo importante: no se intentó guardar nada.
      expect(repositorio.recibido, isNull);
    });

    testWidgets('antes del primer intento no hay nada en rojo', (tester) async {
      await abrirFormulario(tester);

      expect(find.text('Ponle un nombre al reto.'), findsNothing);
    });

    testWidgets('el error de un campo desaparece al escribir en él', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await tocarCrear(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Corre 5 km hoy').first,
        'Reto nuevo',
      );
      await tester.pump();

      expect(find.text('Ponle un nombre al reto.'), findsNothing);
      // Los demás siguen marcados: solo se corrigió uno.
      expect(find.text('Indica la meta en kilómetros.'), findsOneWidget);
    });

    testWidgets('una meta en cero no llega a la base', (tester) async {
      await abrirFormulario(tester);
      await llenar(tester, meta: '0');

      await tocarCrear(tester);

      expect(find.text('La meta debe ser mayor que cero.'), findsOneWidget);
      expect(repositorio.recibido, isNull);
    });

    testWidgets('una XP en cero tampoco', (tester) async {
      await abrirFormulario(tester);
      await llenar(tester, xp: '0');

      await tocarCrear(tester);

      expect(find.text('La XP debe ser mayor que cero.'), findsOneWidget);
      expect(repositorio.recibido, isNull);
    });

    testWidgets('elegir la periodicidad quita su error al instante', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await tocarCrear(tester);

      await tester.tap(find.text('Semanal'));
      await tester.pump();

      expect(find.text('Elige cada cuánto se renueva.'), findsNothing);
    });
  });

  group('vigencia calculada (SCRUM-142)', () {
    testWidgets('sin periodicidad elegida todavía no hay fechas', (
      tester,
    ) async {
      await abrirFormulario(tester);

      expect(find.text('Elige la periodicidad'), findsOneWidget);
    });

    testWidgets('un reto diario empieza y termina hoy', (tester) async {
      await abrirFormulario(tester);

      await tester.tap(find.text('Diario'));
      await tester.pump();

      expect(find.text('Hoy, miércoles 23 de septiembre'), findsOneWidget);
    });

    testWidgets('uno semanal va del lunes al domingo', (tester) async {
      await abrirFormulario(tester);

      await tester.tap(find.text('Semanal'));
      await tester.pump();

      expect(
        find.text('Del lunes 21 de septiembre al domingo 27 de septiembre'),
        findsOneWidget,
      );
    });

    testWidgets('uno mensual, del primero al último día del mes', (
      tester,
    ) async {
      await abrirFormulario(tester);

      await tester.tap(find.text('Mensual'));
      await tester.pump();

      expect(
        find.text('Del martes 1 de septiembre al miércoles 30 de septiembre'),
        findsOneWidget,
      );
    });

    testWidgets('no hay ningún campo para escribir fechas', (tester) async {
      await abrirFormulario(tester);
      await tester.tap(find.text('Semanal'));
      await tester.pump();

      // Los campos de texto son exactamente cuatro: nombre, descripción,
      // meta y XP. La vigencia se muestra, no se edita.
      expect(find.byType(TextField), findsNWidgets(4));
    });
  });

  group('aviso de período ya empezado', () {
    testWidgets('un reto semanal creado el miércoles avisa del recorte', (
      tester,
    ) async {
      await abrirFormulario(tester);

      await tester.tap(find.text('Semanal'));
      await tester.pump();

      expect(
        find.text('Quedan 5 de 7 días: el período ya empezó.'),
        findsOneWidget,
      );
    });

    testWidgets('uno diario no avisa: empieza y termina hoy', (tester) async {
      await abrirFormulario(tester);

      await tester.tap(find.text('Diario'));
      await tester.pump();

      expect(find.byKey(FormularioRetoScreen.claveRecorte), findsNothing);
    });

    testWidgets('uno mensual avisa con los días que quedan del mes', (
      tester,
    ) async {
      await abrirFormulario(tester);

      await tester.tap(find.text('Mensual'));
      await tester.pump();

      expect(
        find.text('Quedan 8 de 30 días: el período ya empezó.'),
        findsOneWidget,
      );
    });
  });

  group('creación', () {
    testWidgets('con los datos completos registra el reto y vuelve', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await llenar(tester, periodicidad: PeriodicidadReto.semanal);

      await tocarCrear(tester);

      expect(repositorio.recibido, isNotNull);
      expect(repositorio.recibido!.nombre, 'Corre 5 km hoy');
      expect(repositorio.recibido!.metaKm, 5);
      expect(repositorio.recibido!.xpOtorgada, 50);
      // La vigencia la puso el formulario, no el administrador.
      expect(repositorio.recibido!.vigencia.inicio, DateTime(2026, 9, 21));
      expect(find.text('Gestión'), findsOneWidget);
    });

    testWidgets('el estado no se manda: lo pone la base (SCRUM-145)', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await llenar(tester);

      await tocarCrear(tester);

      expect(repositorio.recibido!.aSupabase().containsKey('estado'), isFalse);
    });

    testWidgets('si la cuenta no es administradora lo dice y no se sale', (
      tester,
    ) async {
      await abrirFormulario(tester);
      await llenar(tester);
      repositorio.error = const SoloAdministradorException();

      await tocarCrear(tester);

      expect(find.text(CreacionReto.soloAdministrador), findsOneWidget);
      // Sigue en el formulario, con lo escrito intacto para reintentar.
      expect(find.text('Gestión'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Una sola sesión de carrera.'),
        findsOneWidget,
      );
    });

    testWidgets('si falla la red avisa sin perder lo escrito', (tester) async {
      await abrirFormulario(tester);
      await llenar(tester);
      repositorio.error = Exception('sin conexión');

      await tocarCrear(tester);

      expect(find.text(CreacionReto.noSePudo), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Una sola sesión de carrera.'),
        findsOneWidget,
      );
    });
  });
}
