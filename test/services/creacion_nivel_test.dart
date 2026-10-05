import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/nuevo_nivel.dart';
import 'package:traza/services/niveles_provider.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

import '../utiles/niveles_falso.dart';

/// Pruebas del camino que une la validación con el guardado (SCRUM-182).
void main() {
  const existentes = [
    Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100),
    Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500),
  ];

  late NivelesFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = NivelesFalso(catalogo: existentes);
    container = ProviderContainer(
      overrides: [nivelesRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoCreacionNivel> crear(BorradorNivel borrador) =>
      container.read(creacionNivelProvider).crear(borrador, existentes);

  test('con los datos bien, registra el nivel', () async {
    final resultado = await crear(
      const BorradorNivel(nombre: 'Oro', umbral: '1500'),
    );

    expect(resultado, isA<NivelCreado>());
    expect(
      repositorio.recibido,
      const NuevoNivel(nombre: 'Oro', umbralExperiencia: 1500),
    );
  });

  test('un borrador inválido no llega a la base', () async {
    final resultado = await crear(const BorradorNivel(umbral: '0'));

    expect(resultado, isA<NivelConErrores>());
    expect((resultado as NivelConErrores).errores.keys, {
      CampoNivel.nombre,
      CampoNivel.umbral,
    });
    expect(repositorio.recibido, isNull);
  });

  test('si otro administrador se adelantó, marca el campo repetido', () async {
    // El listado con el que se validó ya no estaba al día.
    repositorio.errorAlCrear = const NivelDuplicadoException.porUmbral();

    final resultado = await crear(
      const BorradorNivel(nombre: 'Oro', umbral: '1500'),
    );

    expect((resultado as NivelConErrores).errores, {
      CampoNivel.umbral: CreacionNivel.umbralOcupado,
    });
  });

  test('si otro administrador usó ese nombre, marca el campo del '
      'nombre', () async {
    repositorio.errorAlCrear = const NivelDuplicadoException.porNombre();

    final resultado = await crear(
      const BorradorNivel(nombre: 'Oro', umbral: '1500'),
    );

    expect((resultado as NivelConErrores).errores, {
      CampoNivel.nombre: CreacionNivel.nombreOcupado,
    });
  });

  test('si la base rechaza los datos, lo dice sin marcar campos', () async {
    // Señal de que las restricciones de la tabla y la validación de Dart se
    // desalinearon: no hay campo que señalar porque el borrador era válido.
    repositorio.errorAlCrear = const DatosDeNivelInvalidosException(
      'niveles_umbral_positivo',
    );

    final resultado = await crear(
      const BorradorNivel(nombre: 'Oro', umbral: '1500'),
    );

    expect(
      (resultado as NivelNoGuardado).mensaje,
      CreacionNivel.datosRechazados,
    );
  });

  test(
    'si la cuenta no es administradora, lo dice sin perder lo escrito',
    () async {
      repositorio.errorAlCrear = const SoloAdministradorException();

      final resultado = await crear(
        const BorradorNivel(nombre: 'Oro', umbral: '1500'),
      );

      expect(
        (resultado as NivelNoGuardado).mensaje,
        CreacionNivel.soloAdministrador,
      );
    },
  );

  test('sin sesión también lo dice', () async {
    repositorio.errorAlCrear = const SesionRequeridaException();

    final resultado = await crear(
      const BorradorNivel(nombre: 'Oro', umbral: '1500'),
    );

    expect((resultado as NivelNoGuardado).mensaje, CreacionNivel.sinSesion);
  });

  test('ante un fallo cualquiera, invita a reintentar', () async {
    repositorio.errorAlCrear = StateError('sin conexión');

    final resultado = await crear(
      const BorradorNivel(nombre: 'Oro', umbral: '1500'),
    );

    expect((resultado as NivelNoGuardado).mensaje, CreacionNivel.noSePudo);
  });

  test('el catálogo trae lo que devuelve el repositorio', () async {
    expect(await container.read(catalogoNivelesProvider.future), existentes);
  });
}
