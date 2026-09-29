import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/nuevo_nivel.dart';

/// Pruebas de los modelos de nivel (SCRUM-180).
void main() {
  group('Nivel.desdeSupabase', () {
    test('lee una fila de niveles', () {
      final nivel = Nivel.desdeSupabase(const {
        'id': 'n-1',
        'nombre': 'Bronce',
        'umbral_experiencia': 100,
        'creado_por': 'usuario-1',
        'fecha_creacion': '2026-09-24T03:00:00+00:00',
      });

      expect(nivel.id, 'n-1');
      expect(nivel.nombre, 'Bronce');
      expect(nivel.umbralExperiencia, 100);
    });

    test('una fila incompleta o con tipos raros no se disimula', () {
      // Un `umbral_experiencia` de texto significaría que la tabla y el modelo
      // se desalinearon; eso se arregla, no se rellena con un valor inventado.
      expect(
        () => Nivel.desdeSupabase(const {
          'id': 'n-1',
          'nombre': 'Bronce',
          'umbral_experiencia': 'cien',
        }),
        throwsFormatException,
      );
      expect(
        () => Nivel.desdeSupabase(const {'id': 'n-1', 'nombre': 'Bronce'}),
        throwsFormatException,
      );
    });

    test('dos niveles con el mismo id son el mismo nivel', () {
      const uno = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
      const otro = Nivel(id: 'n-1', nombre: 'Plata', umbralExperiencia: 500);

      expect(uno, otro);
      expect(uno.hashCode, otro.hashCode);
    });
  });

  group('NuevoNivel', () {
    test('arma las columnas que espera Supabase', () {
      const nivel = NuevoNivel(nombre: 'Plata', umbralExperiencia: 500);

      expect(nivel.aSupabase(), {'nombre': 'Plata', 'umbral_experiencia': 500});
    });

    test('no manda creado_por: lo pone el repositorio con la sesión', () {
      const nivel = NuevoNivel(nombre: 'Plata', umbralExperiencia: 500);

      expect(nivel.aSupabase().containsKey('creado_por'), isFalse);
    });

    test('dos niveles con el mismo nombre y umbral son iguales', () {
      const uno = NuevoNivel(nombre: 'Oro', umbralExperiencia: 1500);
      const otro = NuevoNivel(nombre: 'Oro', umbralExperiencia: 1500);

      expect(uno, otro);
      expect(uno.hashCode, otro.hashCode);
      expect(uno, isNot(const NuevoNivel(nombre: 'Oro', umbralExperiencia: 2)));
    });
  });
}
