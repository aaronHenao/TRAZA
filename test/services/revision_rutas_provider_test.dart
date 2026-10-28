import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/revision_ruta.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/foro_service.dart';
import 'package:traza/services/revision_rutas_provider.dart';
import 'package:traza/services/revision_rutas_service.dart';

import '../utiles/revision_rutas_falso.dart';
import '../utiles/rutas_repository_falso.dart';

/// Lo que la app hace al decidir sobre una ruta (SCRUM-321).
void main() {
  late RevisionRutasFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = RevisionRutasFalso(
      rutas: [
        rutaDePrueba(id: 'nueva'),
        rutaDePrueba(id: 'aprobada', estado: EstadoRuta.revisionExperto),
      ],
    );
    container = ProviderContainer(
      overrides: [
        revisionRutasRepositoryProvider.overrideWithValue(repositorio),
        usuarioActualProvider.overrideWithValue(() => 'revisor-1'),
      ],
    );
    addTearDown(container.dispose);
  });

  Ruta ruta(String id) => repositorio.rutas.firstWhere((r) => r.id == id);

  Future<ResultadoRevisionRuta> decidir(
    String id, {
    required bool aprobar,
    String? motivo,
  }) => container
      .read(decisionRevisionRutaProvider)
      .decidir(ruta(id), aprobar: aprobar, motivo: motivo);

  group('bandeja del administrador', () {
    test(
      'trae solo lo recien enviado, no lo que ya espera al experto',
      () async {
        final delAdmin = await container.read(rutasPorRevisarProvider.future);

        expect(delAdmin.map((r) => r.id), ['nueva']);
      },
    );
  });

  group('aprobar', () {
    test('el administrador la manda al Runner Experto (criterio 2)', () async {
      final resultado = await decidir('nueva', aprobar: true);

      expect(resultado, isA<RutaRevisada>());
      final revisada = (resultado as RutaRevisada).ruta;
      expect(revisada.estado, EstadoRuta.revisionExperto);
      expect(revisada.publicada, isFalse);
      expect(
        DecisionRevisionRuta.hecho(revisada),
        'Aprobada. Pasa a un Runner Experto.',
      );
    });

    test('el Runner Experto no aprueba por aqui: aprobar es asignar la '
        'dificultad (0048)', () async {
      final resultado = await decidir('aprobada', aprobar: true);

      expect(
        (resultado as RevisionNoGuardada).mensaje,
        DecisionRevisionRuta.sinPermiso,
      );
      expect(ruta('aprobada').estado, EstadoRuta.revisionExperto);
    });

    test('al aprobar no se manda el motivo aunque se haya escrito', () async {
      await decidir('nueva', aprobar: true, motivo: 'sobra');

      expect(repositorio.decisiones.single.$3, isNull);
    });

    test('lo aprobado sale de la bandeja del administrador', () async {
      await container.read(rutasPorRevisarProvider.future);

      await decidir('nueva', aprobar: true);

      final delAdmin = await container.read(rutasPorRevisarProvider.future);
      expect(delAdmin, isEmpty);
    });
  });

  group('rechazar (criterios 3, 5 y 6)', () {
    test('con motivo la deja rechazada y no la pasa de etapa', () async {
      final resultado = await decidir(
        'nueva',
        aprobar: false,
        motivo: '  Cruza una autopista  ',
      );

      final revisada = (resultado as RutaRevisada).ruta;
      expect(revisada.estado, EstadoRuta.rechazada);
      expect(revisada.motivoRechazo, 'Cruza una autopista');
      expect(repositorio.decisiones.single, (
        'nueva',
        false,
        'Cruza una autopista',
      ));
    });

    test('el Runner Experto tambien puede rechazar', () async {
      final resultado = await decidir(
        'aprobada',
        aprobar: false,
        motivo: 'No es apta para principiantes',
      );

      expect((resultado as RutaRevisada).ruta.estado, EstadoRuta.rechazada);
    });

    test('sin motivo no se completa ni se va a la base', () async {
      for (final motivo in [null, '', '    ']) {
        final resultado = await decidir(
          'nueva',
          aprobar: false,
          motivo: motivo,
        );

        expect(resultado, isA<RevisionSinMotivo>(), reason: '"$motivo"');
        expect(
          (resultado as RevisionSinMotivo).mensaje,
          'El motivo es obligatorio.',
        );
      }
      expect(repositorio.decisiones, isEmpty);
      expect(ruta('nueva').estado, EstadoRuta.enRevision);
    });

    test('un motivo demasiado largo tampoco se manda', () async {
      final resultado = await decidir(
        'nueva',
        aprobar: false,
        motivo: 'a' * (maxCaracteresMotivoRechazo + 1),
      );

      expect(resultado, isA<RevisionSinMotivo>());
      expect(repositorio.decisiones, isEmpty);
    });
  });

  group('lo que puede salir mal', () {
    test('si otro revisor decidio primero lo dice', () async {
      repositorio.errorAlDecidir = const RutaYaRevisadaException();

      final resultado = await decidir('nueva', aprobar: true);

      expect(resultado, isA<RevisionYaResuelta>());
    });

    test('sin el rol de la etapa no se guarda', () async {
      repositorio.errorAlDecidir = const RevisionNoPermitidaException();

      final resultado = await decidir('nueva', aprobar: true);

      expect(resultado, isA<RevisionNoGuardada>());
      expect(
        (resultado as RevisionNoGuardada).mensaje,
        DecisionRevisionRuta.sinPermiso,
      );
    });

    test('si la base rechaza el motivo, se trata como sin motivo', () async {
      repositorio.errorAlDecidir = const MotivoDeRechazoInvalidoException(
        'Rechazar una ruta exige un motivo',
      );

      final resultado = await decidir(
        'nueva',
        aprobar: false,
        motivo: 'Valido para la app',
      );

      expect(resultado, isA<RevisionSinMotivo>());
    });

    test('un fallo de red no se queda sin respuesta', () async {
      repositorio.errorAlDecidir = Exception('sin conexion');

      final resultado = await decidir('nueva', aprobar: true);

      expect(
        (resultado as RevisionNoGuardada).mensaje,
        DecisionRevisionRuta.noSePudo,
      );
    });
  });
}
