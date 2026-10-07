import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_provider.dart';
import 'package:traza/services/retos_service.dart';

import '../utiles/retos_repository_falso.dart';

/// Doble que retira como lo haría la base: la fila se queda, cambia de
/// estado y deja de salir en el catálogo.
class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso({this.error});

  final Object? error;

  /// El catálogo que ve el administrador.
  final List<Reto> catalogo = [];

  Reto? pedido;

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) async =>
      catalogo.where((reto) => reto.estado == EstadoReto.activo).toList();

  /// Los retos del corredor llevan el reto embebido, así que reflejan el
  /// estado en que esté el catálogo en ese momento.
  @override
  Future<List<RetoDelUsuario>> misRetos() async => [
    for (final reto in catalogo)
      RetoDelUsuario(
        reto: reto,
        estado: EstadoRetoUsuario.completado,
        progresoKm: reto.metaKm,
        fechaActivacion: DateTime(2026, 10, 6),
        fechaCompletado: DateTime(2026, 10, 7),
      ),
  ];

  @override
  Future<Reto> retirar(Reto reto) async {
    if (error != null) throw error!;
    pedido = reto;

    final retirado = Reto(
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

    final donde = catalogo.indexWhere((otro) => otro.id == reto.id);
    if (donde >= 0) catalogo[donde] = retirado;

    return retirado;
  }
}

/// Retirada de retos: baja lógica, no borrado (SCRUM-155 y SCRUM-157).
void main() {
  final ahora = DateTime(2026, 10, 20, 9);
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

  ProviderContainer contenedor({Object? error}) {
    repositorio = _RetosFalso(error: error)..catalogo.add(publicado);
    final container = ProviderContainer(
      overrides: [
        retosRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ResultadoRetirada> retirar({Object? error}) =>
      contenedor(error: error).read(retiradaRetoProvider).retirar(publicado);

  group('retirada exitosa (criterio 2)', () {
    test('el reto queda retirado, no borrado', () async {
      final resultado = await retirar();

      expect(resultado, isA<RetoRetirado>());
      expect((resultado as RetoRetirado).reto.estado, EstadoReto.retirado);
      // La fila sigue en su sitio: es lo que sostiene el historial y la XP
      // que ya recibieron los corredores (criterio 3).
      expect(repositorio.catalogo.single.id, 'r1');
    });

    test('se retira el reto que se eligió', () async {
      await retirar();

      expect(repositorio.pedido?.id, 'r1');
    });

    test('deja de salir en el catálogo (SCRUM-158)', () async {
      final container = contenedor();
      container.listen(catalogoRetosProvider, (_, _) {});
      expect(await container.read(catalogoRetosProvider.future), hasLength(1));

      await container.read(retiradaRetoProvider).retirar(publicado);

      expect(await container.read(catalogoRetosProvider.future), isEmpty);
    });
  });

  group('lo del corredor sobrevive (criterio 3)', () {
    test('sus retos siguen ahí, con el reto ya retirado', () async {
      final container = contenedor();
      container.listen(misRetosProvider, (_, _) {});
      final antes = await container.read(misRetosProvider.future);
      expect(antes.single.reto.estaActivo, isTrue);

      await container.read(retiradaRetoProvider).retirar(publicado);
      final despues = await container.read(misRetosProvider.future);

      // Ni desaparece ni pierde lo conseguido: solo deja de estar publicado.
      expect(despues.single.reto.estado, EstadoReto.retirado);
      expect(despues.single.completado, isTrue);
      expect(despues.single.progresoKm, 15);
    });
  });

  group('cuando no se puede retirar', () {
    test('con corredores que todavía pueden cumplirlo, se explica', () async {
      // El plazo sigue abierto y alguien lo tiene en curso: retirarlo le
      // quitaría la XP que está a punto de ganar (SCRUM-159).
      final resultado = await retirar(
        error: const RetoConCorredoresEnJuegoException(),
      );

      expect(
        (resultado as RetoNoRetirado).mensaje,
        RetiradaReto.corredoresEnJuego,
      );
    });

    test('quien no es administrador no retira nada', () async {
      final resultado = await retirar(
        error: const SoloAdministradorException(),
      );

      expect(
        (resultado as RetoNoRetirado).mensaje,
        RetiradaReto.soloAdministrador,
      );
    });

    test('sin sesión se pide iniciarla', () async {
      final resultado = await retirar(
        error: const SesionRequeridaParaRetosException(),
      );

      expect((resultado as RetoNoRetirado).mensaje, RetiradaReto.sinSesion);
    });

    test('un fallo de red se traduce a un mensaje reintentable', () async {
      final resultado = await retirar(error: Exception('sin red'));

      expect((resultado as RetoNoRetirado).mensaje, RetiradaReto.noSePudo);
    });

    test('si no se retiró, el catálogo se queda como estaba', () async {
      final container = contenedor(
        error: const RetoConCorredoresEnJuegoException(),
      );
      container.listen(catalogoRetosProvider, (_, _) {});
      await container.read(catalogoRetosProvider.future);

      await container.read(retiradaRetoProvider).retirar(publicado);

      expect(await container.read(catalogoRetosProvider.future), hasLength(1));
    });
  });
}
