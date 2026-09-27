import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/progresion.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;
import 'package:traza/services/progresion_provider.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';

/// Pruebas del servicio que arma la progresión del corredor (SCRUM-186).
void main() {
  const bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
  const plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
  const niveles = [bronce, plata];

  late NivelesFalso repositorioNiveles;
  late ExperienciaFalsa repositorioExperiencia;

  ProviderContainer contenedor() {
    final container = ProviderContainer(
      overrides: [
        nivelesRepositoryProvider.overrideWithValue(repositorioNiveles),
        experienciaRepositoryProvider.overrideWithValue(repositorioExperiencia),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<Progresion> progresion() =>
      contenedor().read(progresionProvider.future);

  setUp(() {
    repositorioNiveles = NivelesFalso(catalogo: niveles);
    repositorioExperiencia = ExperienciaFalsa(acumulada: 300);
  });

  test(
    'ubica la experiencia acumulada entre los umbrales registrados',
    () async {
      final resultado = await progresion();

      expect(resultado.nivelActual, bronce);
      expect(resultado.siguienteNivel, plata);
      expect(resultado.experiencia, 300);
      expect(resultado.experienciaFaltante, 200);
    },
  );

  test('toma la experiencia tal cual se la dan, no la recalcula', () async {
    // El servicio no sabe de entrenamientos ni de retos: solo pregunta cuánta
    // XP hay acreditada y la usa.
    repositorioExperiencia.acumulada = 640;

    expect((await progresion()).experiencia, 640);
    expect(repositorioExperiencia.consultas, 1);
  });

  test(
    'sin niveles configurados no hay progresión, pero tampoco error',
    () async {
      repositorioNiveles.catalogo = const [];

      final resultado = await progresion();

      expect(resultado.hayNiveles, isFalse);
      expect(resultado.experiencia, 300);
    },
  );

  test('en el nivel más alto no hay siguiente que consultar', () async {
    repositorioExperiencia.acumulada = 900;

    final resultado = await progresion();

    expect(resultado.enNivelMaximo, isTrue);
    expect(resultado.siguienteNivel, isNull);
  });

  test('si los niveles no se pueden leer, el error llega tal cual', () async {
    // Sin envolver: la pantalla distingue "no hay sesión" de un fallo de red.
    repositorioNiveles.errorAlListar = const SesionRequeridaException();

    await expectLater(progresion(), throwsA(isA<SesionRequeridaException>()));
  });

  test('si la experiencia no se puede leer, el error llega tal cual', () async {
    repositorioExperiencia.error = StateError('sin conexión');

    await expectLater(progresion(), throwsA(isA<StateError>()));
  });

  test('al volver a consultar refleja la experiencia nueva', () async {
    // Criterio 5: el corredor completó un reto entre una visita y la
    // siguiente, y la progresión lo muestra sin recalcular nada.
    final container = contenedor();

    expect(
      (await container.read(progresionProvider.future)).nivelActual,
      bronce,
    );

    repositorioExperiencia.acumulada = 700;
    container.invalidate(progresionProvider);

    expect(
      (await container.read(progresionProvider.future)).nivelActual,
      plata,
    );
  });

  group('mientras no exista el motor de experiencia', () {
    test('la experiencia acreditada es cero, no un valor inventado', () async {
      // Hoy nada en la app otorga XP ni la persiste.
      expect(await const ExperienciaSinMotor().experienciaAcumulada(), 0);
    });

    test('con cero el corredor va camino del primer nivel', () async {
      repositorioExperiencia.acumulada = 0;

      final resultado = await progresion();

      expect(resultado.nivelActual, isNull);
      expect(resultado.siguienteNivel, bronce);
      expect(resultado.experienciaFaltante, 100);
    });
  });
}
