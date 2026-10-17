import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/experiencia_ganada.dart';
import 'package:traza/models/regla_experiencia.dart';

/// Pruebas de la lectura de la XP de un entrenamiento (SCRUM-203, SCRUM-205).
void main() {
  Map<String, dynamic> actividad(int cantidad, String ajuste) => {
    'origen': 'actividad',
    'cantidad': cantidad,
    'ajuste': ajuste,
    'retos_usuario': null,
  };

  Map<String, dynamic> reto(int cantidad, String? nombre) => {
    'origen': 'reto',
    'cantidad': cantidad,
    'ajuste': null,
    'retos_usuario': nombre == null
        ? null
        : {
            'retos': {'nombre': nombre},
          },
  };

  group('ExperienciaDeEntrenamiento.desdeFilas', () {
    test('lee la XP de la actividad y su ajuste', () {
      final xp = ExperienciaDeEntrenamiento.desdeFilas([
        actividad(70, 'tope_diario'),
      ]);

      expect(
        xp,
        const ExperienciaDeEntrenamiento(
          xpActividad: 70,
          ajuste: AjusteExperiencia.topeDiario,
        ),
      );
      expect(xp!.total, 70);
    });

    test('suma los retos completados al total, en cualquier orden', () {
      final xp = ExperienciaDeEntrenamiento.desdeFilas([
        reto(400, 'Diez km'),
        actividad(30, 'ninguno'),
        reto(150, 'Semana activa'),
      ])!;

      expect(xp.xpActividad, 30);
      expect(xp.retos, const [
        RetoCompletado(nombre: 'Diez km', xp: 400),
        RetoCompletado(nombre: 'Semana activa', xp: 150),
      ]);
      expect(xp.total, 580);
    });

    test('una actividad sin XP también es un resultado, no un vacío', () {
      final xp = ExperienciaDeEntrenamiento.desdeFilas([
        actividad(0, 'velocidad_imposible'),
      ]);

      expect(xp?.xpActividad, 0);
      expect(xp?.ajuste, AjusteExperiencia.velocidadImposible);
    });

    test('lee todos los ajustes que escribe la base', () {
      const esperados = {
        'ninguno': AjusteExperiencia.ninguno,
        'sin_datos': AjusteExperiencia.sinDatos,
        'velocidad_imposible': AjusteExperiencia.velocidadImposible,
        'menos_del_minimo': AjusteExperiencia.menosDelMinimo,
        'tope_diario': AjusteExperiencia.topeDiario,
      };

      esperados.forEach((texto, ajuste) {
        expect(
          ExperienciaDeEntrenamiento.desdeFilas([actividad(0, texto)])!.ajuste,
          ajuste,
        );
      });
    });

    test('sin fila de actividad el entrenamiento no se procesó', () {
      // Finalizado antes de la migración, o la XP falló y el trigger dejó
      // cerrar el entrenamiento sin ella.
      expect(ExperienciaDeEntrenamiento.desdeFilas([]), isNull);
    });

    test('un reto que el usuario ya no puede ver sale con nombre genérico', () {
      // Si el administrador lo retiró, RLS esconde el reto y el nombre llega
      // vacío; la XP ganada sigue contando.
      final xp = ExperienciaDeEntrenamiento.desdeFilas([
        actividad(25, 'ninguno'),
        reto(400, null),
      ])!;

      expect(
        xp.retos.single.nombre,
        ExperienciaDeEntrenamiento.nombreRetoOculto,
      );
      expect(xp.total, 425);
    });

    test('una fila que no encaja con el esquema no se disimula', () {
      expect(
        () => ExperienciaDeEntrenamiento.desdeFilas([
          actividad(10, 'ajuste_inventado'),
        ]),
        throwsFormatException,
      );
      expect(
        () => ExperienciaDeEntrenamiento.desdeFilas([
          {'origen': 'bono', 'cantidad': 10},
        ]),
        throwsFormatException,
      );
      expect(
        () => ExperienciaDeEntrenamiento.desdeFilas([
          {'origen': 'actividad', 'ajuste': 'ninguno'},
        ]),
        throwsFormatException,
      );
    });
  });
}
