/// Objetivos deportivos que el usuario puede elegir en su perfil.
///
/// Los nombres del enum coinciden con los valores aceptados por la restricción
/// `tipo in ('distancia', 'frecuencia')` de la tabla `objetivos`
/// (`supabase/migrations/0001_init_sprint1.sql`), así que [valorDb] no necesita
/// ninguna traducción.
///
/// Los valores por defecto salen del prototipo (`docs/prototipo.html`). La
/// distancia admite decimales, baja hasta 0.1 km y no lleva tope: la meta la
/// decide el usuario. La frecuencia sí lo lleva, porque la semana tiene siete
/// días.
enum TipoObjetivo {
  distancia(
    etiqueta: 'Distancia semanal',
    descripcion: 'Define cuántos km quieres correr por semana',
    unidad: 'km por semana',
    nombreValor: 'la distancia',
    valorPorDefecto: 10,
    minimo: 0.1,
    maximo: null,
    permiteDecimales: true,
    maxCaracteres: 8,
  ),
  frecuencia(
    etiqueta: 'Frecuencia de entrenamiento',
    descripcion: 'Define cuántas veces por semana quieres entrenar',
    unidad: 'veces por semana',
    nombreValor: 'la frecuencia',
    valorPorDefecto: 3,
    minimo: 1,
    maximo: 7,
    permiteDecimales: false,
    maxCaracteres: 1,
  );

  const TipoObjetivo({
    required this.etiqueta,
    required this.descripcion,
    required this.unidad,
    required this.nombreValor,
    required this.valorPorDefecto,
    required this.minimo,
    required this.maximo,
    required this.permiteDecimales,
    required this.maxCaracteres,
  });

  /// Título de la tarjeta.
  final String etiqueta;

  /// Texto de apoyo bajo el título.
  final String descripcion;

  /// Unidad que acompaña al campo ("km por semana").
  final String unidad;

  /// Cómo se nombra el valor en los mensajes ("la distancia").
  final String nombreValor;

  final num valorPorDefecto;
  final num minimo;

  /// Tope superior, o null si el usuario decide hasta dónde llega.
  final num? maximo;

  final bool permiteDecimales;

  /// Tope de caracteres del campo. No es una regla de negocio: solo evita que
  /// el usuario escriba un número que no cabe en la caja.
  final int maxCaracteres;

  /// Cuántos decimales admite el campo.
  int get maxDecimales => permiteDecimales ? 2 : 0;

  /// Valor que viaja a la columna `tipo` de la tabla `objetivos`.
  String get valorDb => name;
}

/// Muestra 10 en vez de 10.0, conservando los decimales cuando los hay.
String formatearValorObjetivo(num valor) =>
    valor == valor.truncateToDouble() ? '${valor.toInt()}' : '$valor';
