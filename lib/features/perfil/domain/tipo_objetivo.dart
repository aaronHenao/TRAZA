/// Objetivos deportivos que el usuario puede elegir en su perfil.
///
/// Los nombres del enum coinciden con los valores aceptados por la restricción
/// `tipo in ('distancia', 'frecuencia')` de la tabla `objetivos`
/// (`supabase/migrations/0001_init_sprint1.sql`), así que [valorDb] no necesita
/// ninguna traducción.
enum TipoObjetivo {
  distancia(
    etiqueta: 'Distancia semanal',
    descripcion: 'Define cuántos km quieres correr por semana',
    unidad: 'km por semana',
  ),
  frecuencia(
    etiqueta: 'Frecuencia de entrenamiento',
    descripcion: 'Define cuántas veces por semana quieres entrenar',
    unidad: 'veces por semana',
  );

  const TipoObjetivo({
    required this.etiqueta,
    required this.descripcion,
    required this.unidad,
  });

  final String etiqueta;
  final String descripcion;
  final String unidad;

  /// Valor que viaja a la columna `tipo` de la tabla `objetivos`.
  String get valorDb => name;
}
