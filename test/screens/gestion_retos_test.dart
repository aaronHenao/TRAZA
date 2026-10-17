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
import 'package:traza/services/retos_provider.dart';
import 'package:traza/services/retos_service.dart';

import '../utiles/retos_repository_falso.dart';

/// Catálogo de mentira: responde a las tres consultas de la gestión como lo
/// haría la base, para poder comprobar cuál se pide en cada pestaña.
class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso(this.retos);

  List<Reto> retos;
  Object? error;
  var consultas = 0;

  /// Lo que responde al preguntar a quién afecta retirar un reto.
  CorredoresDelReto corredores = (enProgreso: 0, completados: 0, maximoKm: 0.0);

  /// Con qué falla la retirada, si tiene que fallar.
  Object? errorAlRetirar;

  Reto? retirado;

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

  @override
  Future<CorredoresDelReto> corredoresDe(Reto reto) async => corredores;

  @override
  Future<Reto> retirar(Reto reto) async {
    final error = errorAlRetirar;
    if (error != null) throw error;
    retirado = reto;

    // Como la base: la fila se queda, con otro estado.
    final baja = Reto(
      id: reto.id,
      nombre: reto.nombre,
      descripcion: reto.descripcion,
      periodicidad: reto.periodicidad,
      metaKm: reto.metaKm,
      xpOtorgada: reto.xpOtorgada,
      vigencia: reto.vigencia,
      estado: EstadoReto.retirado,
      tipoActividad: reto.tipoActividad,
    );
    retos = [
      for (final otro in retos)
        if (otro.id == reto.id) baja else otro,
    ];

    return baja;
  }
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

  group('retirar un reto (SCRUM-161 y SCRUM-156)', () {
    /// El botón de la primera tarjeta, "Corre 5 km hoy".
    final clave = GestionRetosScreen.claveRetirar(catalogo.first);

    Future<void> tocarRetirar(WidgetTester tester) async {
      await tester.tap(find.byKey(clave));
      await tester.pumpAndSettle();
    }

    testWidgets('cada reto activo tiene por dónde retirarlo', (tester) async {
      await abrirGestion(tester);

      expect(find.byKey(clave), findsOneWidget);
    });

    testWidgets('los ya retirados no se retiran otra vez', (tester) async {
      await abrirGestion(tester);
      await tocarFiltro(
        tester,
        GestionRetosScreen.claveVista(VistaGestionRetos.retirados),
      );

      expect(find.text('Trote de 8 km'), findsOneWidget);
      expect(
        find.byKey(GestionRetosScreen.claveRetirar(catalogo[3])),
        findsNothing,
      );
    });

    testWidgets('no retira nada sin preguntar antes (criterio 1)', (
      tester,
    ) async {
      await abrirGestion(tester);

      await tocarRetirar(tester);

      expect(find.text('¿Retirar este reto?'), findsOneWidget);
      expect(repositorio.retirado, isNull);
      // Sigue en la gestión: el botón no abre el formulario de edición.
      expect(find.text('Gestión de retos'), findsOneWidget);
    });

    testWidgets('dice de qué reto se trata y que no se deshace', (
      tester,
    ) async {
      await abrirGestion(tester);

      await tocarRetirar(tester);

      expect(
        find.textContaining('«Corre 5 km hoy» dejará de aparecer'),
        findsOneWidget,
      );
    });

    testWidgets('cancelar deja el reto donde estaba', (tester) async {
      await abrirGestion(tester);
      await tocarRetirar(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repositorio.retirado, isNull);
      expect(find.text('Corre 5 km hoy'), findsOneWidget);
    });

    testWidgets('confirmar lo retira y lo dice (criterio 2)', (tester) async {
      await abrirGestion(tester);
      await tocarRetirar(tester);

      await tester.tap(find.byKey(GestionRetosScreen.claveConfirmarRetirada));
      await tester.pumpAndSettle();

      expect(repositorio.retirado?.id, '1');
      expect(find.text('Reto retirado del catálogo'), findsOneWidget);
      // Y desaparece de la pestaña de vigentes, sin recargar a mano.
      expect(find.text('Corre 5 km hoy'), findsNothing);
    });

    testWidgets('a quien lo completó se le conserva lo ganado (criterio 3)', (
      tester,
    ) async {
      await abrirGestion(tester);
      repositorio.corredores = (enProgreso: 0, completados: 2, maximoKm: 0.0);

      await tocarRetirar(tester);

      expect(
        find.text(
          '2 lo completaron: conservan su historial y la XP que ganaron.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a quien va en progreso se le advierte que se corta', (
      tester,
    ) async {
      await abrirGestion(tester);
      repositorio.corredores = (enProgreso: 3, completados: 1, maximoKm: 4.0);

      await tocarRetirar(tester);

      expect(
        find.text('3 lo tienen en progreso: no podrán seguir sumándolo.'),
        findsOneWidget,
      );
      expect(
        find.text('1 lo completó: conserva su historial y la XP que ganó.'),
        findsOneWidget,
      );
    });

    testWidgets('si no lo tiene nadie, también se dice', (tester) async {
      await abrirGestion(tester);

      await tocarRetirar(tester);

      expect(
        find.text('Nadie lo ha activado: no afecta a ningún corredor.'),
        findsOneWidget,
      );
    });

    testWidgets('si la base se niega, se explica por qué', (tester) async {
      // El trigger de SCRUM-159: el reto sigue vigente y hay quien puede
      // cerrarlo hoy.
      await abrirGestion(tester);
      repositorio.errorAlRetirar = const RetoConCorredoresEnJuegoException();

      await tocarRetirar(tester);
      await tester.tap(find.byKey(GestionRetosScreen.claveConfirmarRetirada));
      await tester.pumpAndSettle();

      expect(find.text(RetiradaReto.corredoresEnJuego), findsOneWidget);
      expect(find.text('Corre 5 km hoy'), findsOneWidget);
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
      // Es el cuarto de la lista y no tiene por qué caber en pantalla.
      await tester.scrollUntilVisible(find.text('Reto nuevo'), 200);
      expect(find.text('Reto nuevo'), findsOneWidget);
    });
  });
}
