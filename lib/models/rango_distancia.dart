/// Los rangos para filtrar las rutas por su distancia total (HU-37,
/// SCRUM-272).
///
/// No salen del prototipo: se definieron con el equipo en el planning. Van
/// de la más corta a la más larga, que es como se leen en la fila.
enum RangoDistancia {
  menosDe5('Menos de 5 km'),
  de5a10('5 a 10 km'),
  de10a20('10 a 20 km'),
  masDe20('Más de 20 km');

  const RangoDistancia(this.etiqueta);

  /// Lo que dice su chip.
  final String etiqueta;
}
