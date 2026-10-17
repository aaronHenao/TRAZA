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

/// Repositorio de mentira que anota qué se le mandó activar y responde lo que
/// la prueba le indique.
class _RetosFalso extends RetosRepositorioFalso {
  _RetosFalso({this.alActivar, this.mios = const []});

  /// Qué hace al activar. Por defecto, devolver la fila recién creada.
  final RetoDelUsuario Function(Reto reto)? alActivar;

  List<RetoDelUsuario> mios;
  List<Reto> retosVigentes = const [];
  final activados = <Reto>[];

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) async => retosVigentes;

  @override
  Future<RetoDelUsuario> activar(Reto reto) async {
    activados.add(reto);
    final hecho = alActivar;
    if (hecho != null) return hecho(reto);
    return RetoDelUsuario(
      reto: reto,
      estado: EstadoRetoUsuario.enProgreso,
      progresoKm: 0,
      fechaActivacion: DateTime(2026, 10, 3, 9),
    );
  }

  @override
  Future<List<RetoDelUsuario>> misRetos() async => mios;
}

/// Activar un reto (SCRUM-168 y SCRUM-172), con sus dos negativas: el mismo
/// reto dos veces (SCRUM-169) y otro del mismo hueco.
void main() {
  // Sábado 3 de octubre de 2026.
  final ahora = DateTime(2026, 10, 3, 9);

  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');
  const trote = TipoActividad(id: 'tipo-trote', nombre: 'Trote');

  Reto reto({
    String id = 'r1',
    String nombre = 'Corre 5 km hoy',
    PeriodicidadReto periodicidad = PeriodicidadReto.diaria,
    TipoActividad tipo = correr,
    DateTime? inicio,
    DateTime? fin,
  }) => Reto(
    id: id,
    nombre: nombre,
    descripcion: 'Qué hay que hacer.',
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

  RetoDelUsuario mio(Reto cual) => RetoDelUsuario(
    reto: cual,
    estado: EstadoRetoUsuario.enProgreso,
    progresoKm: 0,
    fechaActivacion: ahora,
  );

  ProviderContainer contenedor(_RetosFalso repositorio) {
    final container = ProviderContainer(
      overrides: [
        retosRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('activación', () {
    test('registra el reto y devuelve lo que guardó la base', () async {
      final repositorio = _RetosFalso();
      final container = contenedor(repositorio);

      final resultado = await container
          .read(activacionRetoProvider)
          .activar(reto());

      expect(resultado, isA<RetoActivado>());
      expect(repositorio.activados.single.id, 'r1');
      // Arranca en cero: activar no es haber corrido nada todavía.
      expect((resultado as RetoActivado).mio.progresoKm, 0);
      expect(resultado.mio.estado, EstadoRetoUsuario.enProgreso);
    });

    test('el mismo reto dos veces no se duplica y se dice distinto '
        '(SCRUM-169)', () async {
      final repositorio = _RetosFalso(
        alActivar: (_) => throw const RetoYaActivadoException(),
      );
      final container = contenedor(repositorio);

      final resultado = await container
          .read(activacionRetoProvider)
          .activar(reto());

      expect(resultado, isA<RetoNoActivado>());
      expect((resultado as RetoNoActivado).mensaje, ActivacionReto.yaActivado);
    });

    test('otro reto del mismo hueco dice cuál lo impide', () async {
      final repositorio = _RetosFalso(
        alActivar: (_) => throw const RetoDelMismoHuecoException(),
      );
      final container = contenedor(repositorio);

      final resultado = await container
          .read(activacionRetoProvider)
          .activar(reto(nombre: 'Corre 10 km hoy'));

      // Nombra el hueco, no el reto: lo que hay que soltar es el otro.
      expect(
        (resultado as RetoNoActivado).mensaje,
        'Ya tienes un reto diario de Correr en curso.',
      );
    });

    test('sin sesión lo dice en vez de culpar a la red', () async {
      final repositorio = _RetosFalso(
        alActivar: (_) => throw const SesionRequeridaParaRetosException(),
      );
      final container = contenedor(repositorio);

      final resultado = await container
          .read(activacionRetoProvider)
          .activar(reto());

      expect((resultado as RetoNoActivado).mensaje, ActivacionReto.sinSesion);
    });

    test('un fallo cualquiera se traduce a un mensaje reintentable', () async {
      final repositorio = _RetosFalso(
        alActivar: (_) => throw Exception('sin red'),
      );
      final container = contenedor(repositorio);

      final resultado = await container
          .read(activacionRetoProvider)
          .activar(reto());

      expect((resultado as RetoNoActivado).mensaje, ActivacionReto.noSePudo);
    });
  });

  group('un reto por periodicidad y tipo de actividad', () {
    test('otro del mismo hueco lo bloquea', () {
      final llevo = mio(reto(id: 'r1'));

      expect(
        motivoDeBloqueo(reto(id: 'r2'), [llevo]),
        'Ya tienes un reto diario de Correr en curso.',
      );
    });

    test('el mismo plazo con otra actividad no estorba', () {
      final llevo = mio(reto(id: 'r1', tipo: correr));

      expect(motivoDeBloqueo(reto(id: 'r2', tipo: trote), [llevo]), isNull);
    });

    test('la misma actividad con otra periodicidad tampoco', () {
      final llevo = mio(reto(id: 'r1'));
      final semanal = reto(
        id: 'r2',
        periodicidad: PeriodicidadReto.semanal,
        inicio: DateTime(2026, 9, 28),
        fin: DateTime(2026, 10, 4),
      );

      expect(motivoDeBloqueo(semanal, [llevo]), isNull);
    });

    test('el de mañana no choca con el de hoy', () {
      // Lo que se compara son las vigencias, no el día en que se mira: así la
      // regla no depende de en qué día vive el teléfono.
      final llevo = mio(reto(id: 'r1'));
      final maniana = reto(
        id: 'r2',
        inicio: DateTime(2026, 10, 4),
        fin: DateTime(2026, 10, 4),
      );

      expect(motivoDeBloqueo(maniana, [llevo]), isNull);
    });

    test('un plazo que se solapa a medias sí choca', () {
      final llevo = mio(
        reto(
          id: 'r1',
          periodicidad: PeriodicidadReto.semanal,
          inicio: DateTime(2026, 9, 28),
          fin: DateTime(2026, 10, 4),
        ),
      );
      final siguiente = reto(
        id: 'r2',
        periodicidad: PeriodicidadReto.semanal,
        inicio: DateTime(2026, 10, 4),
        fin: DateTime(2026, 10, 11),
      );

      expect(
        motivoDeBloqueo(siguiente, [llevo]),
        'Ya tienes un reto semanal de Correr en curso.',
      );
    });

    test('sin nada en curso no hay nada que bloquee', () {
      expect(motivoDeBloqueo(reto(), const []), isNull);
    });
  });

  group('reparto entre las dos secciones', () {
    final diarioCorrer = reto(id: 'd-correr');
    final otroDiarioCorrer = reto(id: 'd-correr-2', nombre: 'Corre 10 km hoy');
    final diarioTrote = reto(id: 'd-trote', tipo: trote);

    Future<VistaRetosCorredor> repartir(List<RetoDelUsuario> mios) async {
      final repositorio = _RetosFalso(mios: mios)
        ..retosVigentes = [diarioCorrer, otroDiarioCorrer, diarioTrote];
      final container = contenedor(repositorio);

      // Las dos consultas se resuelven antes de mirar el reparto.
      await container.read(retosVigentesProvider.future);
      await container.read(misRetosProvider.future);
      return container.read(retosCorredorProvider).requireValue;
    }

    test('sin nada activo, todo está disponible y nada bloqueado', () async {
      final vista = await repartir(const []);

      expect(vista.enCurso, isEmpty);
      expect(vista.disponibles, hasLength(3));
      expect(vista.bloqueados, isEmpty);
    });

    test('lo activado sale del catálogo y pasa a en curso', () async {
      final vista = await repartir([mio(diarioCorrer)]);

      expect(vista.enCurso.single.reto.id, 'd-correr');
      // Ya es suyo: ofrecerlo otra vez haría pensar que puede activarlo dos
      // veces.
      expect(vista.disponibles.map((r) => r.id), ['d-correr-2', 'd-trote']);
    });

    test('marca el que comparte hueco y deja libre el de otra '
        'actividad', () async {
      final vista = await repartir([mio(diarioCorrer)]);

      expect(
        vista.bloqueados['d-correr-2'],
        'Ya tienes un reto diario de Correr en curso.',
      );
      expect(vista.bloqueados.containsKey('d-trote'), isFalse);
    });

    test('lo vencido deja de ocupar su hueco', () async {
      // Un reto de anteayer que nadie marcó como vencido: la fila sigue en
      // 'en_progreso', pero su plazo ya pasó.
      final viejo = mio(
        reto(
          id: 'd-viejo',
          inicio: DateTime(2026, 10, 1),
          fin: DateTime(2026, 10, 1),
        ),
      );

      final vista = await repartir([viejo]);

      expect(vista.enCurso, isEmpty);
      expect(vista.bloqueados, isEmpty);
    });
  });
}
