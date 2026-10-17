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
  _RetosFalso({this.error, this.enCurso});

  final Object? error;

  /// Lo que responde al preguntar cómo van los corredores. Nulo para fallar,
  /// como una consulta que no llega.
  final CorredoresDelReto? enCurso;

  CambiosReto? recibido;
  Reto? original;

  /// El catálogo, como lo devolvería la base: lo que `editar` guarda es lo
  /// que la siguiente consulta encuentra.
  final List<Reto> catalogo = [];

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) async =>
      List.of(catalogo);

  @override
  Future<CorredoresDelReto> corredoresDe(Reto reto) async =>
      enCurso ?? (throw Exception('sin red'));

  @override
  Future<Reto> editar(Reto original, CambiosReto cambios) async {
    if (error != null) throw error!;
    this.original = original;
    recibido = cambios;

    // Como la base: devuelve la fila tal como quedó.
    final guardado = Reto(
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

    final donde = catalogo.indexWhere((reto) => reto.id == original.id);
    if (donde >= 0) catalogo[donde] = guardado;

    return guardado;
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

  group('el catálogo se refresca tras guardar (SCRUM-152)', () {
    /// Un contenedor con el catálogo ya cargado, como la pantalla de gestión
    /// cuando el administrador entra a editar.
    Future<(ProviderContainer, _RetosFalso)> conElCatalogoCargado() async {
      final repositorio = _RetosFalso()..catalogo.add(publicado);
      final container = ProviderContainer(
        overrides: [
          retosRepositoryProvider.overrideWithValue(repositorio),
          relojProvider.overrideWithValue(() => ahora),
        ],
      );
      addTearDown(container.dispose);

      // Con alguien escuchando, como la pantalla: el provider es autoDispose
      // y sin suscripción se tiraría entre lecturas, refrescando por su
      // cuenta y sin probar nada.
      container.listen(catalogoRetosProvider, (_, _) {});
      final catalogo = await container.read(catalogoRetosProvider.future);
      expect(catalogo.single.metaKm, 15);

      return (container, repositorio);
    }

    test('el catálogo pasa a dar el reto ya cambiado', () async {
      final (container, _) = await conElCatalogoCargado();

      await container
          .read(edicionRetoProvider)
          .guardar(
            publicado,
            BorradorReto.de(
              publicado,
            ).copyWith(nombre: 'Corre 20 km', meta: '20'),
          );
      final catalogo = await container.read(catalogoRetosProvider.future);

      // Sin que nadie vuelva a entrar a la pantalla: lo pide el provider al
      // quedar invalidado.
      expect(catalogo.single.nombre, 'Corre 20 km');
      expect(catalogo.single.metaKm, 20);
    });

    test('con datos inválidos el catálogo se queda como estaba', () async {
      final (container, _) = await conElCatalogoCargado();

      await container
          .read(edicionRetoProvider)
          .guardar(publicado, BorradorReto.de(publicado).copyWith(meta: '0'));
      final catalogo = await container.read(catalogoRetosProvider.future);

      expect(catalogo.single.metaKm, 15);
    });
  });

  group('cómo van los corredores (SCRUM-151)', () {
    Future<CorredoresDelReto> comoVan({CorredoresDelReto? responde}) async {
      final container = ProviderContainer(
        overrides: [
          retosRepositoryProvider.overrideWithValue(
            _RetosFalso(enCurso: responde),
          ),
          relojProvider.overrideWithValue(() => ahora),
        ],
      );
      addTearDown(container.dispose);
      return container
          .read(edicionRetoProvider)
          .comoVanLosCorredores(publicado);
    }

    test('devuelve cuántos son y lo que lleva el más adelantado', () async {
      final enCurso = await comoVan(
        responde: (enProgreso: 3, completados: 1, maximoKm: 10.4),
      );

      expect(enCurso.enProgreso, 3);
      expect(enCurso.completados, 1);
      expect(enCurso.maximoKm, 10.4);
    });

    test('si la consulta falla, responde que no hay nadie', () async {
      // Ni el aviso ni el bloqueo de la meta son la barrera de verdad: esa es
      // el trigger. No poder contarlos no deja al administrador sin guardar.
      final enCurso = await comoVan();

      expect(enCurso.enProgreso, 0);
      expect(enCurso.maximoKm, 0);
    });
  });
}
