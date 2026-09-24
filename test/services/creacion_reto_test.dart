import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/vigencia_reto.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_provider.dart';
import 'package:traza/services/retos_service.dart';

/// Repositorio de mentira: anota lo que le mandan y responde lo que la prueba
/// le indique.
class _RetosFalso implements RetosRepository {
  Object? error;
  NuevoReto? recibido;
  List<Reto> catalogo = const [];

  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async {
    final error = this.error;
    if (error != null) throw error;
    return catalogo.where((reto) => reto.estado == estado).toList();
  }

  @override
  Future<Reto> crear(NuevoReto reto) async {
    recibido = reto;
    final error = this.error;
    if (error != null) throw error;

    // Como la base: devuelve la fila con el id y el estado que ella pone.
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

/// Pruebas de la creación de retos (SCRUM-143) y del estado activo con el que
/// nacen (SCRUM-145).
void main() {
  // Miércoles 23 de septiembre de 2026.
  final ahora = DateTime(2026, 9, 23, 11, 30);

  const completo = BorradorReto(
    nombre: 'Corre 5 km hoy',
    descripcion: 'Una sola sesión de carrera de al menos 5 km.',
    periodicidad: PeriodicidadReto.diaria,
    meta: '5',
    xp: '50',
  );

  late _RetosFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = _RetosFalso();
    container = ProviderContainer(
      overrides: [
        retosRepositoryProvider.overrideWithValue(repositorio),
        relojProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoCreacionReto> crear(BorradorReto borrador) =>
      container.read(creacionRetoProvider).crear(borrador);

  group('creación exitosa', () {
    test('registra el reto y devuelve lo que guardó la base', () async {
      final resultado = await crear(completo);

      expect(resultado, isA<RetoCreado>());
      expect((resultado as RetoCreado).reto.id, 'reto-1');
      expect(resultado.reto.nombre, 'Corre 5 km hoy');
    });

    test('el reto nace activo (SCRUM-145)', () async {
      final resultado = await crear(completo) as RetoCreado;

      expect(resultado.reto.estado, EstadoReto.activo);
      expect(resultado.reto.estaActivo, isTrue);
    });

    test('la vigencia se calcula con el reloj del momento (SCRUM-142)', () async {
      await crear(completo.copyWith(periodicidad: PeriodicidadReto.semanal));

      expect(repositorio.recibido!.vigencia.inicio, DateTime(2026, 9, 21));
      expect(repositorio.recibido!.vigencia.fin, DateTime(2026, 9, 27));
    });
  });

  group('datos inválidos', () {
    test('no toca la base y devuelve los errores por campo', () async {
      final resultado = await crear(const BorradorReto());

      expect(resultado, isA<RetoConErrores>());
      expect((resultado as RetoConErrores).errores.keys, {
        CampoReto.nombre,
        CampoReto.descripcion,
        CampoReto.periodicidad,
        CampoReto.meta,
        CampoReto.xp,
      });
      // Lo importante: ni se intentó guardar.
      expect(repositorio.recibido, isNull);
    });

    test('una meta en cero no llega a la base', () async {
      final resultado = await crear(completo.copyWith(meta: '0'));

      expect((resultado as RetoConErrores).errores, contains(CampoReto.meta));
      expect(repositorio.recibido, isNull);
    });

    test('una XP en cero tampoco', () async {
      final resultado = await crear(completo.copyWith(xp: '0'));

      expect((resultado as RetoConErrores).errores, contains(CampoReto.xp));
      expect(repositorio.recibido, isNull);
    });
  });

  group('el guardado falla', () {
    test('sin sesión lo dice y no pierde lo escrito', () async {
      repositorio.error = const SesionRequeridaParaRetosException();

      final resultado = await crear(completo);

      expect(resultado, isA<RetoNoGuardado>());
      expect((resultado as RetoNoGuardado).mensaje, CreacionReto.sinSesion);
    });

    test('una cuenta sin rol de administrador recibe un mensaje claro', () async {
      // Es lo que responde Postgres cuando la policy de insert, que exige
      // es_admin(), rechaza la fila.
      repositorio.error = const SoloAdministradorException();

      final resultado = await crear(completo) as RetoNoGuardado;

      expect(resultado.mensaje, CreacionReto.soloAdministrador);
    });

    test('si la base rechaza los datos, se avisa sin culpar a la red', () async {
      repositorio.error = const DatosDeRetoInvalidosException(
        'retos_meta_positiva',
      );

      final resultado = await crear(completo) as RetoNoGuardado;

      expect(resultado.mensaje, CreacionReto.datosRechazados);
    });

    test('un fallo de red se traduce a un mensaje reintentable', () async {
      repositorio.error = Exception('sin conexión');

      final resultado = await crear(completo) as RetoNoGuardado;

      expect(resultado.mensaje, CreacionReto.noSePudo);
    });
  });

  group('lectura de una fila de retos', () {
    final fila = {
      'id': 'reto-9',
      'nombre': 'Mes de 60 km',
      'descripcion': 'Acumula 60 km durante el mes.',
      'periodicidad': 'mensual',
      'meta_km': 60,
      'xp_otorgada': 800,
      'fecha_inicio': '2026-09-01',
      'fecha_fin': '2026-09-30',
      'estado': 'activo',
    };

    test('se lee completa', () {
      final reto = Reto.desdeSupabase(fila);

      expect(reto.id, 'reto-9');
      expect(reto.periodicidad, PeriodicidadReto.mensual);
      expect(reto.metaKm, 60.0);
      expect(reto.xpOtorgada, 800);
      expect(reto.vigencia, VigenciaReto(
        inicio: DateTime(2026, 9, 1),
        fin: DateTime(2026, 9, 30),
      ));
      expect(reto.estaActivo, isTrue);
    });

    test('un reto retirado se reconoce como tal', () {
      final reto = Reto.desdeSupabase({...fila, 'estado': 'retirado'});

      expect(reto.estado, EstadoReto.retirado);
      expect(reto.estaActivo, isFalse);
    });

    test('una fila incompleta falla en vez de inventarse valores', () {
      expect(
        () => Reto.desdeSupabase({...fila}..remove('meta_km')),
        throwsFormatException,
      );
      expect(
        () => Reto.desdeSupabase({...fila, 'periodicidad': 'anual'}),
        throwsFormatException,
      );
    });
  });
}
