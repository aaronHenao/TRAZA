import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/screens/retos/detalle_reto_screen.dart';
import 'package:traza/screens/retos/retos_screen.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/widgets/fila_reto_usuario.dart';
import 'package:traza/widgets/tarjeta_reto.dart';

import '../utiles/retos_repository_falso.dart';

class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso({this.catalogo = const [], this.mios = const []});

  final List<Reto> catalogo;
  final List<RetoDelUsuario> mios;
  final activados = <Reto>[];

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) async => catalogo;

  @override
  Future<List<RetoDelUsuario>> misRetos() async => mios;

  @override
  Future<RetoDelUsuario> activar(Reto reto) async {
    activados.add(reto);
    return RetoDelUsuario(
      reto: reto,
      estado: EstadoRetoUsuario.enProgreso,
      progresoKm: 0,
      fechaActivacion: DateTime(2026, 10, 3, 9),
    );
  }
}

/// Lo que el corredor ve de sus retos activados: la sección "En curso"
/// (SCRUM-170), el botón de activar (SCRUM-168) y el bloqueo de un reto que
/// comparte periodicidad y tipo de actividad con otro que ya lleva.
void main() {
  // Sábado 3 de octubre de 2026.
  final ahora = DateTime(2026, 10, 3, 9);

  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');
  const caminar = TipoActividad(id: 'tipo-caminar', nombre: 'Caminar');

  Reto reto({
    required String id,
    required String nombre,
    TipoActividad tipo = correr,
    PeriodicidadReto periodicidad = PeriodicidadReto.diaria,
    DateTime? inicio,
    DateTime? fin,
  }) => Reto(
    id: id,
    nombre: nombre,
    descripcion: 'Qué hay que hacer en $nombre.',
    periodicidad: periodicidad,
    metaKm: 5,
    xpOtorgada: 50,
    vigencia: VigenciaReto(
      inicio: inicio ?? DateTime(2026, 10, 3),
      fin: fin ?? DateTime(2026, 10, 3),
    ),
    estado: EstadoReto.activo,
    tipoActividad: tipo,
  );

  final correHoy = reto(id: 'c1', nombre: 'Corre 5 km hoy');
  final correMas = reto(id: 'c2', nombre: 'Corre 10 km hoy');
  final caminaHoy = reto(id: 'w1', nombre: 'Camina 2 km hoy', tipo: caminar);

  RetoDelUsuario enCurso(Reto cual, {double progresoKm = 0}) => RetoDelUsuario(
    reto: cual,
    estado: EstadoRetoUsuario.enProgreso,
    progresoKm: progresoKm,
    fechaActivacion: ahora,
  );

  late _RetosFalso repositorio;

  Future<void> abrir(
    WidgetTester tester, {
    List<Reto> catalogo = const [],
    List<RetoDelUsuario> mios = const [],
    String desde = '/retos',
    Reto? detalleDe,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    repositorio = _RetosFalso(catalogo: catalogo, mios: mios);

    final router = GoRouter(
      initialLocation: desde,
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
                reto: state.extra as Reto? ?? detalleDe,
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
    await tester.pumpAndSettle();
  }

  group('sección "En curso" (SCRUM-170)', () {
    testWidgets('no aparece si no hay nada activo', (tester) async {
      await abrir(tester, catalogo: [correHoy]);

      expect(find.byKey(RetosScreen.claveEnCurso), findsNothing);
      // Sin encabezados, la pantalla se lee igual que antes para quien
      // empieza.
      expect(find.text('DISPONIBLES'), findsNothing);
      expect(find.byType(TarjetaReto), findsOneWidget);
    });

    testWidgets('lo activado va arriba, con su progreso', (tester) async {
      await abrir(
        tester,
        catalogo: [correHoy, caminaHoy],
        mios: [enCurso(correHoy, progresoKm: 2)],
      );

      expect(find.byKey(RetosScreen.claveEnCurso), findsOneWidget);
      expect(find.byType(FilaRetoUsuario), findsOneWidget);
      expect(find.text('2 de 5 km'), findsOneWidget);
    });

    testWidgets('lo activado sale del catálogo', (tester) async {
      await abrir(
        tester,
        catalogo: [correHoy, caminaHoy],
        mios: [enCurso(correHoy)],
      );

      expect(find.byKey(TarjetaReto.claveDe('c1')), findsNothing);
      expect(find.byKey(TarjetaReto.claveDe('w1')), findsOneWidget);
    });

    testWidgets('con todo activado, Disponibles lo dice sin sonar a que no '
        'hay retos', (tester) async {
      await abrir(tester, catalogo: [correHoy], mios: [enCurso(correHoy)]);

      expect(find.text('Nada más por ahora'), findsOneWidget);
      expect(find.text('No hay retos disponibles'), findsNothing);
    });

    testWidgets('el filtro es del catálogo: lo activo sigue arriba', (
      tester,
    ) async {
      await abrir(tester, catalogo: [caminaHoy], mios: [enCurso(correHoy)]);

      await tester.tap(
        find.byKey(RetosScreen.clavePestana(PeriodicidadReto.mensual)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilaRetoUsuario), findsOneWidget);
      expect(find.text('Ningún reto mensual'), findsOneWidget);
    });
  });

  group('un reto por periodicidad y tipo de actividad', () {
    testWidgets('el del mismo hueco se marca con su motivo', (tester) async {
      await abrir(
        tester,
        catalogo: [correMas, caminaHoy],
        mios: [enCurso(correHoy)],
      );

      expect(
        find.text('Ya tienes un reto diario de Correr en curso.'),
        findsOneWidget,
      );
    });

    testWidgets('el de otra actividad no se marca', (tester) async {
      await abrir(tester, catalogo: [caminaHoy], mios: [enCurso(correHoy)]);

      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });

    testWidgets('se marca, no se esconde: el reto se sigue pudiendo leer', (
      tester,
    ) async {
      await abrir(tester, catalogo: [correMas], mios: [enCurso(correHoy)]);

      expect(find.byKey(TarjetaReto.claveDe('c2')), findsOneWidget);

      await tester.tap(find.byKey(TarjetaReto.claveDe('c2')));
      await tester.pumpAndSettle();

      expect(find.text('Corre 10 km hoy'), findsOneWidget);
      expect(find.text('PARA CUMPLIRLO'), findsOneWidget);
    });
  });

  group('el pie del detalle (SCRUM-168)', () {
    testWidgets('un reto libre ofrece activarlo', (tester) async {
      await abrir(
        tester,
        catalogo: [correHoy],
        desde: '/retos/c1',
        detalleDe: correHoy,
      );

      expect(find.byKey(DetalleRetoScreen.claveActivar), findsOneWidget);
      expect(find.text('Activar reto'), findsOneWidget);
    });

    testWidgets('activarlo lo registra y vuelve al catálogo', (tester) async {
      await abrir(
        tester,
        catalogo: [correHoy],
        desde: '/retos/c1',
        detalleDe: correHoy,
      );

      await tester.tap(find.byKey(DetalleRetoScreen.claveActivar));
      await tester.pumpAndSettle();

      expect(repositorio.activados.single.id, 'c1');
      expect(find.text('Reto activado. ¡A por él!'), findsOneWidget);
    });

    testWidgets('si ya lo tiene, muestra el progreso en vez del botón', (
      tester,
    ) async {
      await abrir(
        tester,
        catalogo: [correHoy],
        mios: [enCurso(correHoy, progresoKm: 3)],
        desde: '/retos/c1',
        detalleDe: correHoy,
      );

      expect(find.byKey(DetalleRetoScreen.claveActivar), findsNothing);
      expect(find.text('Ya lo tienes activo'), findsOneWidget);
      expect(find.text('3 de 5 km'), findsOneWidget);
    });

    testWidgets('si otro ocupa su hueco, dice cuál en vez del botón', (
      tester,
    ) async {
      await abrir(
        tester,
        catalogo: [correMas],
        mios: [enCurso(correHoy)],
        desde: '/retos/c2',
        detalleDe: correMas,
      );

      expect(find.byKey(DetalleRetoScreen.claveActivar), findsNothing);
      expect(
        find.text('Ya tienes un reto diario de Correr en curso.'),
        findsOneWidget,
      );
      expect(
        find.text('Termínalo o espera a que acabe su plazo para tomar otro.'),
        findsOneWidget,
      );
    });

    testWidgets('el de otra actividad sí se puede activar', (tester) async {
      await abrir(
        tester,
        catalogo: [caminaHoy],
        mios: [enCurso(correHoy)],
        desde: '/retos/w1',
        detalleDe: caminaHoy,
      );

      expect(find.byKey(DetalleRetoScreen.claveActivar), findsOneWidget);
    });
  });
}
