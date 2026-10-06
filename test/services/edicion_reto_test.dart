import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_provider.dart';
import 'package:traza/services/retos_service.dart';

import '../utiles/retos_repository_falso.dart';

/// Doble que anota los cambios recibidos y responde lo que la prueba indique.
class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso({this.error});

  final Object? error;
  CambiosReto? recibido;
  Reto? original;

  @override
  Future<Reto> editar(Reto original, CambiosReto cambios) async {
    if (error != null) throw error!;
    this.original = original;
    recibido = cambios;

    // Como la base: devuelve la fila tal como quedó.
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

/// Guardar los cambios de un reto publicado (SCRUM-147).
void main() {
  final ahora = DateTime(2026, 10, 5, 9);
  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');

  final publicado = Reto(
    id: 'r1',
    nombre: 'Corre 15 km esta semana',
    descripcion: 'Suma 15 km entre lunes y domingo.',
    periodicidad: PeriodicidadReto.semanal,
    metaKm: 15,
    xpOtorgada: 200,
    vigencia: VigenciaReto(
      inicio: DateTime(2026, 10, 5),
      fin: DateTime(2026, 10, 11),
    ),
    estado: EstadoReto.activo,
    tipoActividad: correr,
  );

  late _RetosFalso repositorio;

  Future<ResultadoCreacionReto> guardar(
    BorradorReto borrador, {
    Object? error,
  }) async {
    repositorio = _RetosFalso(error: error);
    final container = ProviderContainer(
      overrides: [
        retosRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(container.dispose);
    return container.read(edicionRetoProvider).guardar(publicado, borrador);
  }

  group('edición exitosa (criterio 1)', () {
    test('guarda los cambios y devuelve el reto como quedó', () async {
      final resultado = await guardar(
        BorradorReto.de(publicado).copyWith(nombre: 'Corre 20 km', meta: '20'),
      );

      expect(resultado, isA<RetoCreado>());
      final guardado = (resultado as RetoCreado).reto;
      expect(guardado.nombre, 'Corre 20 km');
      expect(guardado.metaKm, 20);
      // Lo que no se edita sigue como estaba.
      expect(guardado.periodicidad, PeriodicidadReto.semanal);
      expect(guardado.tipoActividad, correr);
    });

    test('se edita el reto que se abrió, no otro', () async {
      await guardar(BorradorReto.de(publicado));

      expect(repositorio.original?.id, 'r1');
    });

    test('alargar el plazo llega a la base', () async {
      await guardar(
        BorradorReto.de(publicado).copyWith(fin: DateTime(2026, 10, 18)),
      );

      expect(repositorio.recibido!.vigencia.fin, DateTime(2026, 10, 18));
    });
  });

  group('validaciones (criterio 3)', () {
    test('con datos inválidos no se toca la base', () async {
      final resultado = await guardar(
        BorradorReto.de(publicado).copyWith(meta: '0'),
      );

      expect(resultado, isA<RetoConErrores>());
      expect(
        (resultado as RetoConErrores).errores.keys,
        contains(CampoReto.meta),
      );
      // Lo importante: el reto publicado se queda como estaba.
      expect(repositorio.recibido, isNull);
    });

    test('sin nombre tampoco', () async {
      final resultado = await guardar(
        BorradorReto.de(publicado).copyWith(nombre: '  '),
      );

      expect(resultado, isA<RetoConErrores>());
      expect(repositorio.recibido, isNull);
    });
  });

  group('cuando no se puede guardar', () {
    test(
      'una cuenta sin rol de administrador recibe un mensaje claro',
      () async {
        // En un update, RLS no responde "prohibido": deja la fila fuera de
        // alcance y no se actualiza ninguna. El servicio lo traduce.
        final resultado = await guardar(
          BorradorReto.de(publicado),
          error: const SoloAdministradorException(),
        );

        expect(
          (resultado as RetoNoGuardado).mensaje,
          EdicionReto.soloAdministrador,
        );
      },
    );

    test('sin sesión lo dice', () async {
      final resultado = await guardar(
        BorradorReto.de(publicado),
        error: const SesionRequeridaParaRetosException(),
      );

      expect((resultado as RetoNoGuardado).mensaje, EdicionReto.sinSesion);
    });

    test(
      'si la base rechaza el cambio, se avisa sin culpar a la red',
      () async {
        // Es lo que responde el trigger `retos_cambios_permitidos` cuando se
        // intenta mover de sitio un reto por fuera de la pantalla.
        final resultado = await guardar(
          BorradorReto.de(publicado),
          error: const DatosDeRetoInvalidosException(
            'la periodicidad de un reto no se cambia',
          ),
        );

        expect(
          (resultado as RetoNoGuardado).mensaje,
          EdicionReto.datosRechazados,
        );
      },
    );

    test('un fallo de red se traduce a un mensaje reintentable', () async {
      final resultado = await guardar(
        BorradorReto.de(publicado),
        error: Exception('sin red'),
      );

      expect((resultado as RetoNoGuardado).mensaje, EdicionReto.noSePudo);
    });
  });
}
