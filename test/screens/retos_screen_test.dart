import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/screens/retos/detalle_reto_screen.dart';
import 'package:traza/screens/retos/retos_screen.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/widgets/tarjeta_reto.dart';

import '../utiles/retos_repository_falso.dart';

/// Catálogo de mentira: responde lo que la prueba le indique y anota con qué
/// día se le preguntó.
class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso(this.respuesta);

  Future<List<Reto>> Function() respuesta;
  DateTime? diaPedido;
  var consultas = 0;

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) {
    consultas++;
    diaPedido = hoy;
    return respuesta();
  }
}

/// Pruebas del catálogo de retos del corredor (SCRUM-164), su tarjeta
/// (SCRUM-167) y el paso al detalle (SCRUM-165 y SCRUM-166).
void main() {
  // Lunes 28 de septiembre de 2026.
  final ahora = DateTime(2026, 9, 28, 10);

  Reto reto({
    required String id,
    required String nombre,
    required PeriodicidadReto periodicidad,
    required DateTime fin,
    double metaKm = 5,
    int xp = 50,
  }) => Reto(
    id: id,
    nombre: nombre,
    descripcion: 'Qué hay que hacer en $nombre.',
    periodicidad: periodicidad,
    metaKm: metaKm,
    xpOtorgada: xp,
    vigencia: VigenciaReto(inicio: DateTime(2026, 9, 28), fin: fin),
    estado: EstadoReto.activo,
    tipoActividad: const TipoActividad(id: 'tipo-correr', nombre: 'Correr'),
  );

  final diario = reto(
    id: 'd1',
    nombre: 'Corre 5 km hoy',
    periodicidad: PeriodicidadReto.diaria,
    fin: DateTime(2026, 9, 28),
  );
  final semanal = reto(
    id: 's1',
    nombre: 'Corre 15 km esta semana',
    periodicidad: PeriodicidadReto.semanal,
    fin: DateTime(2026, 10, 4),
    metaKm: 15,
    xp: 200,
  );
  final mensual = reto(
    id: 'm1',
    nombre: 'Mes de 60 km',
    periodicidad: PeriodicidadReto.mensual,
    fin: DateTime(2026, 9, 30),
    metaKm: 60,
  );

  late _RetosFalso repositorio;

  Future<void> abrirCatalogo(
    WidgetTester tester, {
    Future<List<Reto>> Function()? respuesta,
    bool esperar = true,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = _RetosFalso(
      respuesta ?? () async => [diario, semanal, mensual],
    );
    final router = GoRouter(
      initialLocation: '/retos',
      routes: [
        GoRoute(
          path: '/retos',
          builder: (_, _) => const RetosScreen(),
          routes: [
            GoRoute(
              path: 'historial',
              builder: (_, _) => const Scaffold(body: Text('Mis retos')),
            ),
            GoRoute(
              path: ':retoId',
              builder: (context, state) => DetalleRetoPorRuta(
                retoId: state.pathParameters['retoId']!,
                reto: state.extra as Reto?,
              ),
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (esperar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> tocarPestana(
    WidgetTester tester,
    PeriodicidadReto? periodicidad,
  ) async {
    final chip = find.byKey(RetosScreen.clavePestana(periodicidad));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  group('catálogo (SCRUM-164)', () {
    testWidgets('muestra los retos vigentes con sus datos', (tester) async {
      await abrirCatalogo(tester);

      expect(find.text('Retos'), findsOneWidget);
      expect(find.text('Corre 5 km hoy'), findsOneWidget);
      expect(find.text('+200 XP'), findsOneWidget);
      expect(find.text('Meta 60 km'), findsOneWidget);
    });

    testWidgets('pregunta por el día de hoy, no por el del servidor', (
      tester,
    ) async {
      // La base está en UTC: si se preguntara por su fecha, un reto diario
      // desaparecería a las 7 de la tarde en Colombia.
      await abrirCatalogo(tester);

      expect(repositorio.diaPedido, ahora);
    });

    testWidgets('sin retos vigentes lo dice sin culpar a nadie', (
      tester,
    ) async {
      await abrirCatalogo(tester, respuesta: () async => []);

      expect(find.text('No hay retos disponibles'), findsOneWidget);
    });

    testWidgets('mientras carga muestra el indicador', (tester) async {
      final pendiente = Completer<List<Reto>>();
      await abrirCatalogo(
        tester,
        respuesta: () => pendiente.future,
        esperar: false,
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pendiente.complete([diario]);
      await tester.pumpAndSettle();
      expect(find.text('Corre 5 km hoy'), findsOneWidget);
    });

    testWidgets('si la consulta falla lo dice y permite reintentar', (
      tester,
    ) async {
      var falla = true;
      await abrirCatalogo(
        tester,
        respuesta: () async {
          if (falla) throw Exception('sin red');
          return [diario];
        },
      );

      expect(find.text('No pudimos cargar los retos'), findsOneWidget);

      falla = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Corre 5 km hoy'), findsOneWidget);
    });
  });

  group('vigencia en la tarjeta (SCRUM-167)', () {
    testWidgets('el último día avisa de que termina hoy', (tester) async {
      await abrirCatalogo(tester, respuesta: () async => [diario]);

      expect(find.text('Termina hoy'), findsOneWidget);
    });

    testWidgets('con un día por delante lo dice en singular', (tester) async {
      final maniana = reto(
        id: 'x',
        nombre: 'Corre mañana',
        periodicidad: PeriodicidadReto.diaria,
        fin: DateTime(2026, 9, 29),
      );
      await abrirCatalogo(tester, respuesta: () async => [maniana]);

      expect(find.text('Queda 1 día'), findsOneWidget);
    });

    testWidgets('con más días, en plural', (tester) async {
      await abrirCatalogo(tester, respuesta: () async => [semanal]);

      // Del 28 de septiembre al 4 de octubre.
      expect(find.text('Quedan 6 días'), findsOneWidget);
    });
  });

  group('pestañas por periodicidad', () {
    testWidgets('arranca en Todos con los tres', (tester) async {
      await abrirCatalogo(tester);

      expect(find.byType(TarjetaReto), findsNWidgets(3));
    });

    testWidgets('elegir Semanal deja solo los semanales', (tester) async {
      await abrirCatalogo(tester);

      await tocarPestana(tester, PeriodicidadReto.semanal);

      expect(find.text('Corre 15 km esta semana'), findsOneWidget);
      expect(find.text('Corre 5 km hoy'), findsNothing);
    });

    testWidgets('filtrar no vuelve a consultar: se resuelve en memoria', (
      tester,
    ) async {
      await abrirCatalogo(tester);
      final antes = repositorio.consultas;

      await tocarPestana(tester, PeriodicidadReto.diaria);

      expect(repositorio.consultas, antes);
    });

    testWidgets('si la pestaña no tiene retos lo distingue del catálogo '
        'vacío', (tester) async {
      await abrirCatalogo(tester, respuesta: () async => [diario]);

      await tocarPestana(tester, PeriodicidadReto.mensual);

      expect(find.text('Ningún reto mensual'), findsOneWidget);
      expect(find.text('No hay retos disponibles'), findsNothing);
    });

    testWidgets('volver a Todos los muestra de nuevo', (tester) async {
      await abrirCatalogo(tester);
      await tocarPestana(tester, PeriodicidadReto.diaria);

      await tocarPestana(tester, null);

      expect(find.byType(TarjetaReto), findsNWidgets(3));
    });
  });

  group('detalle (SCRUM-165 y SCRUM-166)', () {
    testWidgets('tocar una tarjeta abre su detalle', (tester) async {
      await abrirCatalogo(tester);

      await tester.tap(find.byKey(TarjetaReto.claveDe(semanal.id)));
      await tester.pumpAndSettle();

      expect(find.text('Reto'), findsOneWidget);
      expect(find.text('Corre 15 km esta semana'), findsOneWidget);
    });

    testWidgets('dice qué hacer, en qué plazo y cuánta XP da', (tester) async {
      await abrirCatalogo(tester);
      await tester.tap(find.byKey(TarjetaReto.claveDe(semanal.id)));
      await tester.pumpAndSettle();

      expect(find.text('PARA CUMPLIRLO'), findsOneWidget);
      expect(find.text('Recorre 15 km'), findsOneWidget);
      expect(
        find.text('Sumando lo de toda la semana, en las salidas que quieras.'),
        findsOneWidget,
      );
      expect(find.text('Del 28 de septiembre al 4 de octubre'), findsOneWidget);
      expect(find.text('Ganas 200 XP'), findsOneWidget);
    });

    testWidgets('un reto de un solo día lo dice así', (tester) async {
      await abrirCatalogo(tester);
      await tester.tap(find.byKey(TarjetaReto.claveDe(diario.id)));
      await tester.pumpAndSettle();

      expect(find.text('Solo hoy, 28 de septiembre'), findsOneWidget);
      expect(
        find.text('Es el último día: termina esta noche.'),
        findsOneWidget,
      );
    });

    testWidgets('muestra la descripción que escribió el administrador', (
      tester,
    ) async {
      await abrirCatalogo(tester);
      await tester.tap(find.byKey(TarjetaReto.claveDe(diario.id)));
      await tester.pumpAndSettle();

      expect(find.text('DESCRIPCIÓN'), findsOneWidget);
      expect(find.text('Qué hay que hacer en Corre 5 km hoy.'), findsOneWidget);
    });

    testWidgets('volver deja el catálogo como estaba', (tester) async {
      await abrirCatalogo(tester);
      await tester.tap(find.byKey(TarjetaReto.claveDe(diario.id)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();

      expect(find.byType(TarjetaReto), findsNWidgets(3));
    });

    testWidgets('un reto que ya no existe no rompe la pantalla', (
      tester,
    ) async {
      await abrirCatalogo(tester);

      final router = GoRouter.of(tester.element(find.byType(RetosScreen)));
      router.push('/retos/fantasma');
      await tester.pumpAndSettle();

      expect(find.text('Este reto ya no está disponible.'), findsOneWidget);
    });
  });

  testWidgets('el botón de la cabecera lleva al historial', (tester) async {
    await abrirCatalogo(tester);

    await tester.tap(find.byKey(RetosScreen.claveHistorial));
    await tester.pumpAndSettle();

    expect(find.text('Mis retos'), findsOneWidget);
  });
}
