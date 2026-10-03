import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/screens/admin/gestion_retos_screen.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';

import '../utiles/retos_repository_falso.dart';

/// Catálogo de mentira: responde a las tres consultas de la gestión como lo
/// haría la base, para poder comprobar cuál se pide en cada pestaña.
class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso(this.retos);

  List<Reto> retos;
  Object? error;
  var consultas = 0;

  List<Reto> _responder(bool Function(Reto) filtro) {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return retos.where(filtro).toList();
  }

  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async =>
      _responder((reto) => reto.estado == estado);

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) async => _responder(
    (reto) => reto.estaActivo && reto.vigencia.diasRestantesDesde(hoy) > 0,
  );

  @override
  Future<List<Reto>> caducados({required DateTime hoy}) async => _responder(
    (reto) => reto.estaActivo && reto.vigencia.diasRestantesDesde(hoy) == 0,
  );
}

/// Pruebas de la gestión de retos del administrador (SCRUM-139): el catálogo
/// y sus filtros.
void main() {
  final ahora = DateTime(2026, 9, 23, 11, 30);

  Reto reto({
    required String id,
    required String nombre,
    required PeriodicidadReto periodicidad,
    EstadoReto estado = EstadoReto.activo,
    double metaKm = 5,
    int xp = 50,
  }) => Reto(
    id: id,
    nombre: nombre,
    descripcion: 'Descripción de $nombre.',
    periodicidad: periodicidad,
    metaKm: metaKm,
    xpOtorgada: xp,
    vigencia: periodicidad.vigenciaDesde(ahora),
    estado: estado,
    tipoActividad: const TipoActividad(id: 'tipo-correr', nombre: 'Correr'),
  );

  final catalogo = [
    reto(
      id: '1',
      nombre: 'Corre 5 km hoy',
      periodicidad: PeriodicidadReto.diaria,
    ),
    reto(
      id: '2',
      nombre: 'Corre 15 km esta semana',
      periodicidad: PeriodicidadReto.semanal,
      metaKm: 15,
      xp: 200,
    ),
    reto(
      id: '3',
      nombre: 'Mes de 60 km',
      periodicidad: PeriodicidadReto.mensual,
      metaKm: 60,
    ),
    reto(
      id: '4',
      nombre: 'Trote de 8 km',
      periodicidad: PeriodicidadReto.semanal,
      estado: EstadoReto.retirado,
    ),
    // Activo, pero su vigencia terminó hace dos días: ningún corredor puede
    // intentarlo ya.
    Reto(
      id: '5',
      nombre: 'Corre 10 km la semana pasada',
      descripcion: 'Un reto que ya caducó.',
      periodicidad: PeriodicidadReto.semanal,
      metaKm: 10,
      xpOtorgada: 100,
      vigencia: VigenciaReto(
        inicio: DateTime(2026, 9, 14),
        fin: DateTime(2026, 9, 21),
      ),
      estado: EstadoReto.activo,
      tipoActividad: const TipoActividad(id: 'tipo-correr', nombre: 'Correr'),
    ),
  ];

  late _RetosFalso repositorio;

  Future<void> tocarFiltro(WidgetTester tester, Key clave) async {
    final finder = find.byKey(clave);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> abrirGestion(
    WidgetTester tester, {
    List<Reto>? retos,
    Object? error,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = _RetosFalso(retos ?? catalogo)..error = error;
    final router = GoRouter(
      initialLocation: '/admin/retos',
      routes: [
        GoRoute(
          path: '/admin/retos',
          builder: (_, _) => const GestionRetosScreen(),
        ),
        GoRoute(
          path: '/admin/retos/nuevo',
          builder: (_, _) => const Scaffold(body: Text('Formulario')),
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
    await tester.pumpAndSettle();
  }

  group('catálogo', () {
    testWidgets('muestra los retos activos con sus datos', (tester) async {
      await abrirGestion(tester);

      expect(find.text('Gestión de retos'), findsOneWidget);
      // El distintivo del rol vive en el panel, no aquí (SCRUM-194).
      expect(find.text('Administrador'), findsNothing);
      expect(find.text('Corre 5 km hoy'), findsOneWidget);
      expect(find.text('+200 XP'), findsOneWidget);
      expect(find.text('Meta 60 km'), findsOneWidget);
    });

    testWidgets('el reto retirado no sale entre los activos', (tester) async {
      await abrirGestion(tester);

      expect(find.text('Trote de 8 km'), findsNothing);
    });

    testWidgets('la meta sin decimales se muestra entera', (tester) async {
      await abrirGestion(tester);

      expect(find.text('Meta 5 km'), findsOneWidget);
    });

    testWidgets('sin retos invita a crear el primero', (tester) async {
      await abrirGestion(tester, retos: []);

      expect(find.text('No hay retos vigentes'), findsOneWidget);
      expect(find.text('Toca el botón + para publicar uno.'), findsOneWidget);
    });

    testWidgets('si la consulta falla lo dice y permite reintentar', (
      tester,
    ) async {
      await abrirGestion(tester, error: Exception('sin red'));

      expect(find.text('No pudimos cargar los retos'), findsOneWidget);

      repositorio.error = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Corre 5 km hoy'), findsOneWidget);
    });
  });

  group('filtro por periodicidad', () {
    testWidgets('arranca en Todos, con los tres retos activos', (tester) async {
      await abrirGestion(tester);

      expect(find.text('Corre 5 km hoy'), findsOneWidget);
      expect(find.text('Corre 15 km esta semana'), findsOneWidget);
      expect(find.text('Mes de 60 km'), findsOneWidget);
    });

    testWidgets('elegir Semanal deja solo los semanales', (tester) async {
      await abrirGestion(tester);

      await tocarFiltro(
        tester,
        GestionRetosScreen.clavePeriodicidad(PeriodicidadReto.semanal),
      );

      expect(find.text('Corre 15 km esta semana'), findsOneWidget);
      expect(find.text('Corre 5 km hoy'), findsNothing);
      expect(find.text('Mes de 60 km'), findsNothing);
    });

    testWidgets('filtrar no vuelve a consultar: se resuelve en memoria', (
      tester,
    ) async {
      await abrirGestion(tester);
      final antes = repositorio.consultas;

      await tocarFiltro(
        tester,
        GestionRetosScreen.clavePeriodicidad(PeriodicidadReto.diaria),
      );

      expect(repositorio.consultas, antes);
    });

    testWidgets('volver a Todos los muestra de nuevo', (tester) async {
      await abrirGestion(tester);
      await tocarFiltro(
        tester,
        GestionRetosScreen.clavePeriodicidad(PeriodicidadReto.diaria),
      );

      await tocarFiltro(tester, GestionRetosScreen.clavePeriodicidad(null));

      expect(find.text('Mes de 60 km'), findsOneWidget);
    });

    testWidgets('si el filtro no encuentra nada lo distingue de estar vacío', (
      tester,
    ) async {
      await abrirGestion(tester, retos: [catalogo.first]);

      await tocarFiltro(
        tester,
        GestionRetosScreen.clavePeriodicidad(PeriodicidadReto.mensual),
      );

      // Nombra la periodicidad y la pestaña: un mensaje común obligaría a
      // mirar qué está activo para entenderlo.
      expect(find.text('Ningún reto mensual en vigentes'), findsOneWidget);
      expect(find.text('No hay retos vigentes'), findsNothing);
    });
  });

  group('filtro por estado', () {
    testWidgets('Retirados consulta de nuevo y trae los dados de baja', (
      tester,
    ) async {
      await abrirGestion(tester);

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.retirados),
      );

      expect(find.text('Trote de 8 km'), findsOneWidget);
      expect(find.text('Corre 5 km hoy'), findsNothing);
    });

    testWidgets('el estado sí va a la consulta, no se filtra en memoria', (
      tester,
    ) async {
      await abrirGestion(tester);
      final antes = repositorio.consultas;

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.retirados),
      );

      expect(repositorio.consultas, greaterThan(antes));
    });

    testWidgets('la insignia dice la situación real, no el campo estado', (
      tester,
    ) async {
      // Un reto activo con la vigencia cumplida diría "Vigente" si se leyera
      // solo `estado`, justo dentro de la pestaña de caducados.
      await abrirGestion(tester);
      expect(find.text('Vigente'), findsNWidgets(3));

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.caducados),
      );
      expect(find.text('Caducado'), findsOneWidget);
      expect(find.text('Vigente'), findsNothing);

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.retirados),
      );
      expect(find.text('Retirado'), findsOneWidget);
    });
  });

  group('las tres vistas', () {
    testWidgets('Vigentes deja fuera lo caducado y lo retirado', (
      tester,
    ) async {
      await abrirGestion(tester);

      expect(find.text('Corre 5 km hoy'), findsOneWidget);
      // Activo, pero su vigencia terminó: ningún corredor puede intentarlo.
      expect(find.text('Corre 10 km la semana pasada'), findsNothing);
      expect(find.text('Trote de 8 km'), findsNothing);
    });

    testWidgets('Caducados trae lo activo con la vigencia cumplida', (
      tester,
    ) async {
      await abrirGestion(tester);

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.caducados),
      );

      expect(find.text('Corre 10 km la semana pasada'), findsOneWidget);
      expect(find.text('Corre 5 km hoy'), findsNothing);
    });

    testWidgets('cada vista es una consulta distinta, no un filtro en '
        'memoria', (tester) async {
      // Separar lo vigente de lo caducado depende de la fecha de hoy, que la
      // base no conoce: está en UTC.
      await abrirGestion(tester);
      final antes = repositorio.consultas;

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.caducados),
      );

      expect(repositorio.consultas, greaterThan(antes));
    });

    testWidgets('cada vista vacía dice lo suyo', (tester) async {
      await abrirGestion(tester, retos: [catalogo.first]);

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.caducados),
      );
      expect(find.text('Ningún reto ha caducado'), findsOneWidget);

      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.retirados),
      );
      expect(find.text('No has retirado ningún reto'), findsOneWidget);
    });
  });

  group('crear un reto', () {
    testWidgets('el botón + abre el formulario', (tester) async {
      await abrirGestion(tester);

      await tester.tap(find.byKey(GestionRetosScreen.claveBotonNuevo));
      await tester.pumpAndSettle();

      expect(find.text('Formulario'), findsOneWidget);
    });

    testWidgets('al volver del formulario el catálogo se vuelve a consultar', (
      tester,
    ) async {
      await abrirGestion(tester);
      final antes = repositorio.consultas;

      await tester.tap(find.byKey(GestionRetosScreen.claveBotonNuevo));
      await tester.pumpAndSettle();
      // El reto que se acaba de crear tiene que aparecer al volver.
      repositorio.retos = [
        ...catalogo,
        reto(
          id: '9',
          nombre: 'Reto nuevo',
          periodicidad: PeriodicidadReto.diaria,
        ),
      ];
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      expect(repositorio.consultas, greaterThan(antes));
      expect(find.text('Reto nuevo'), findsOneWidget);
    });
  });
}
