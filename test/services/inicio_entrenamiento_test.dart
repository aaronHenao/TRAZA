import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/actividad_provider.dart';
import 'package:traza/services/entrenamiento_actual_provider.dart';
import 'package:traza/services/entrenamiento_provider.dart';
import 'package:traza/services/entrenamiento_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;
import 'package:traza/services/tipos_actividad_service.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/services/ubicacion_provider.dart';

/// Pruebas del inicio del entrenamiento (SCRUM-99): crear la fila de
/// `entrenamientos` con la actividad elegida y dejar su id como el
/// entrenamiento en curso, para que los puntos GPS tengan dueño.
///
/// En rutas oficiales, etapa 3, el entrenamiento puede nacer asociado a la
/// ruta que el corredor eligió en el detalle, y esa ruta queda en curso.
import '../utiles/fuente_ubicacion_falsa.dart';
import '../utiles/rutas_repository_falso.dart';

void main() {
  late _EntrenamientosFalso repositorio;
  late FuenteUbicacionFalsa gps;
  late ProviderContainer container;

  /// Container con el catálogo de actividades cargado, como en la pantalla de
  /// inicio con sesión abierta.
  ProviderContainer crearContainer({
    List<TipoActividad> catalogo = const [
      TipoActividad(id: 'id-correr', nombre: 'Correr'),
      TipoActividad(id: 'id-trote', nombre: 'Trote'),
    ],
  }) {
    final c = ProviderContainer(
      overrides: [
        entrenamientoRepositoryProvider.overrideWithValue(repositorio),
        fuenteUbicacionProvider.overrideWithValue(gps),
        tiposActividadRepositoryProvider.overrideWithValue(
          _TiposActividadFalso(catalogo),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Espera a que el catálogo cargue, como hace la pantalla al abrirse.
  Future<void> cargarCatalogo() async {
    await container.read(tiposActividadProvider.future);
  }

  Future<String?> iniciar() =>
      container.read(inicioEntrenamientoProvider).iniciar();

  String? enCurso() => container.read(entrenamientoActualProvider);

  setUp(() {
    repositorio = _EntrenamientosFalso();
    gps = FuenteUbicacionFalsa();
    addTearDown(() => gps.cerrar());
  });

  group('crear el entrenamiento', () {
    test('lo crea con el tipo de actividad elegido', () async {
      container = crearContainer();
      await cargarCatalogo();

      final error = await iniciar();

      expect(error, isNull);
      expect(repositorio.creados, ['id-correr']);
    });

    test('usa el tipo que el usuario cambió en los chips', () async {
      container = crearContainer();
      await cargarCatalogo();
      container
          .read(actividadSeleccionadaProvider.notifier)
          .seleccionar(const TipoActividad(id: 'id-trote', nombre: 'Trote'));

      await iniciar();

      expect(repositorio.creados, ['id-trote']);
    });

    test('deja el id nuevo como el entrenamiento en curso', () async {
      container = crearContainer();
      await cargarCatalogo();
      expect(enCurso(), isNull);

      await iniciar();

      expect(enCurso(), 'entrenamiento-1');
    });

    test('un entrenamiento nuevo reemplaza al anterior', () async {
      container = crearContainer();
      await cargarCatalogo();

      await iniciar();
      expect(enCurso(), 'entrenamiento-1');
      await iniciar();

      expect(enCurso(), 'entrenamiento-2');
      expect(repositorio.creados.length, 2);
    });
  });

  group('cuando no se puede iniciar (SCRUM-100)', () {
    test('sin configuración de inicio avisa y no llama a la base', () async {
      // Sin sesión el catálogo es el local, cuyos tipos no traen id.
      container = crearContainer(catalogo: TipoActividad.catalogoLocal);
      await cargarCatalogo();

      final error = await iniciar();

      expect(error, InicioEntrenamiento.sinSesion);
      expect(repositorio.creados, isEmpty);
      expect(enCurso(), isNull);
    });

    test('sin catálogo cargado todavía no hay actividad que iniciar', () async {
      container = crearContainer(catalogo: const []);
      await cargarCatalogo();

      final error = await iniciar();

      expect(error, InicioEntrenamiento.sinSesion);
      expect(repositorio.creados, isEmpty);
    });

    test(
      'si la sesión se cerró entre medias avisa que inicie sesión',
      () async {
        container = crearContainer();
        await cargarCatalogo();
        repositorio.error = const SesionRequeridaException();

        final error = await iniciar();

        expect(error, InicioEntrenamiento.sinSesion);
        expect(enCurso(), isNull);
      },
    );

    test('con la ubicación del teléfono apagada no crea nada', () async {
      container = crearContainer();
      await cargarCatalogo();
      gps.servicio = false;

      final error = await iniciar();

      expect(error, InicioEntrenamiento.ubicacionApagada);
      expect(repositorio.creados, isEmpty);
      expect(enCurso(), isNull);
    });

    test('al encender la ubicación se puede iniciar', () async {
      container = crearContainer();
      await cargarCatalogo();
      gps.servicio = false;
      expect(await iniciar(), InicioEntrenamiento.ubicacionApagada);

      gps.servicio = true;
      final error = await iniciar();

      expect(error, isNull);
      expect(repositorio.creados, ['id-correr']);
    });

    test('si la base falla avisa que se intente de nuevo', () async {
      container = crearContainer();
      await cargarCatalogo();
      repositorio.error = StateError('sin red');

      final error = await iniciar();

      expect(error, InicioEntrenamiento.noSePudo);
      expect(enCurso(), isNull, reason: 'no queda un entrenamiento a medias');
    });

    test('tras un fallo se puede volver a intentar', () async {
      container = crearContainer();
      await cargarCatalogo();
      repositorio.error = StateError('sin red');
      expect(await iniciar(), InicioEntrenamiento.noSePudo);

      repositorio.error = null;
      final error = await iniciar();

      expect(error, isNull);
      expect(enCurso(), 'entrenamiento-1');
    });
  });

  group('correr una ruta oficial (rutas oficiales, etapa 3)', () {
    Ruta? rutaEnCurso() => container.read(rutaEnCursoProvider);

    test('con ruta, el entrenamiento se crea asociado a ella y con la '
        'actividad elegida en los chips', () async {
      container = crearContainer();
      await cargarCatalogo();
      container
          .read(actividadSeleccionadaProvider.notifier)
          .seleccionar(const TipoActividad(id: 'id-trote', nombre: 'Trote'));

      final error = await container
          .read(inicioEntrenamientoProvider)
          .iniciar(ruta: _estadio);

      expect(error, isNull);
      expect(repositorio.creados, ['id-trote']);
      expect(repositorio.rutas, ['ruta-estadio']);
      expect(enCurso(), 'entrenamiento-1');
    });

    test(
      'sin ruta, el entrenamiento se crea sin rutaId, como hasta ahora',
      () async {
        container = crearContainer();
        await cargarCatalogo();

        await iniciar();

        expect(repositorio.creados, ['id-correr']);
        expect(repositorio.rutas, [null]);
      },
    );

    test(
      'si se crea con ruta, la ruta queda en curso con su trazado',
      () async {
        container = crearContainer();
        await cargarCatalogo();
        expect(rutaEnCurso(), isNull);

        await container
            .read(inicioEntrenamientoProvider)
            .iniciar(ruta: _estadio);

        expect(rutaEnCurso()?.id, 'ruta-estadio');
        // El trazado es lo que el tracking dibuja como guía.
        expect(rutaEnCurso()?.trazado, _estadio.trazado);
      },
    );

    test('si se crea sin ruta, no queda ninguna en curso aunque hubiera una '
        'de antes', () async {
      container = crearContainer();
      await cargarCatalogo();
      container.read(rutaEnCursoProvider.notifier).fijar(_estadio);

      final error = await iniciar();

      expect(error, isNull);
      expect(rutaEnCurso(), isNull);
    });

    test('si la base falla, no toca la ruta en curso', () async {
      container = crearContainer();
      await cargarCatalogo();
      repositorio.error = StateError('sin red');

      final error = await container
          .read(inicioEntrenamientoProvider)
          .iniciar(ruta: _estadio);

      expect(error, InicioEntrenamiento.noSePudo);
      expect(rutaEnCurso(), isNull);
    });

    test('si falla, conserva la ruta en curso que ya había', () async {
      container = crearContainer();
      await cargarCatalogo();
      container.read(rutaEnCursoProvider.notifier).fijar(_nutibara);
      repositorio.error = StateError('sin red');

      await container.read(inicioEntrenamientoProvider).iniciar(ruta: _estadio);

      expect(rutaEnCurso()?.id, 'ruta-nutibara');
    });

    test('con la ubicación del teléfono apagada no crea nada ni deja la ruta '
        'en curso', () async {
      container = crearContainer();
      await cargarCatalogo();
      gps.servicio = false;

      final error = await container
          .read(inicioEntrenamientoProvider)
          .iniciar(ruta: _estadio);

      expect(error, InicioEntrenamiento.ubicacionApagada);
      expect(repositorio.creados, isEmpty);
      expect(rutaEnCurso(), isNull);
    });

    test('sin sesión no crea nada ni deja la ruta en curso', () async {
      container = crearContainer(catalogo: TipoActividad.catalogoLocal);
      await cargarCatalogo();

      final error = await container
          .read(inicioEntrenamientoProvider)
          .iniciar(ruta: _estadio);

      expect(error, InicioEntrenamiento.sinSesion);
      expect(repositorio.creados, isEmpty);
      expect(rutaEnCurso(), isNull);
    });
  });

  group('entrenamiento en curso', () {
    test('empieza sin ninguno', () {
      container = crearContainer();

      expect(enCurso(), isNull);
    });

    test('se libera cuando la actividad termina', () async {
      container = crearContainer();
      await cargarCatalogo();
      await iniciar();

      container.read(entrenamientoEnCursoProvider.notifier).limpiar();

      expect(enCurso(), isNull);
    });
  });
}

/// Una ruta oficial, completa: con el trazado que el detalle carga antes de
/// ofrecer correrla (rutas oficiales, etapa 3).
final _estadio = rutaDePrueba(
  id: 'ruta-estadio',
  nombre: 'Vuelta al estadio',
  estado: EstadoRuta.publicada,
  trazado: const [
    PuntoRuta(latitud: 6.2442, longitud: -75.5812),
    PuntoRuta(latitud: 6.2450, longitud: -75.5800),
  ],
);

final _nutibara = rutaDePrueba(
  id: 'ruta-nutibara',
  nombre: 'Cerro Nutibara',
  estado: EstadoRuta.publicada,
);

/// Entrenamientos en memoria: anota cada creación y, si la prueba lo indica,
/// falla.
class _EntrenamientosFalso implements EntrenamientoRepository {
  /// `tipo_actividad_id` de cada entrenamiento creado, en orden.
  final creados = <String>[];

  /// `ruta_id` de cada entrenamiento creado, en el mismo orden que
  /// [creados]: null si se creó sin ruta (rutas oficiales, etapa 3).
  final rutas = <String?>[];

  /// Si no es null, `crear` lo lanza.
  Object? error;

  @override
  Future<String> crear({
    required String tipoActividadId,
    String? rutaId,
  }) async {
    final error = this.error;
    if (error != null) throw error;
    creados.add(tipoActividadId);
    rutas.add(rutaId);
    return 'entrenamiento-${creados.length}';
  }

  @override
  Future<void> finalizar({
    required String entrenamientoId,
    required DateTime fechaFin,
    required Duration duracion,
    double? distanciaMetros,
  }) => throw UnimplementedError('El inicio no cierra entrenamientos');

  @override
  Future<void> cancelar({
    required String entrenamientoId,
    required DateTime fechaFin,
  }) => throw UnimplementedError('El inicio no descarta entrenamientos');

  @override
  Future<ResumenEntrenamiento?> cargarFinalizado(String entrenamientoId) =>
      throw UnimplementedError('El inicio no lee entrenamientos');
}

class _TiposActividadFalso implements TiposActividadRepository {
  const _TiposActividadFalso(this.tipos);

  final List<TipoActividad> tipos;

  @override
  Future<List<TipoActividad>> cargar() async => tipos;
}
