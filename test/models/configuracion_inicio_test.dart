import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/configuracion_inicio.dart';
import 'package:traza/models/tipo_actividad.dart';

/// Pruebas de la configuración de inicio (SCRUM-93).
void main() {
  test('con un tipo de la base arma la configuración con su id y su nombre', () {
    expect(
      ConfiguracionInicio.para(
        const TipoActividad(id: 'id-trote', nombre: 'Trote'),
      ),
      const ConfiguracionInicio(
        tipoActividadId: 'id-trote',
        nombreActividad: 'Trote',
      ),
    );
  });

  test('sin tipo elegido no hay configuración', () {
    expect(ConfiguracionInicio.para(null), isNull);
  });

  test('con un tipo del catálogo local, sin sesión, no hay configuración', () {
    // Sin id, la base rechazaría el entrenamiento: no hay que ofrecer
    // iniciarlo.
    for (final tipo in TipoActividad.catalogoLocal) {
      expect(ConfiguracionInicio.para(tipo), isNull, reason: tipo.nombre);
    }
  });
}
