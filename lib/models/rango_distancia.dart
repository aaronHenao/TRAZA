/// Los rangos para filtrar las rutas por su distancia total (HU-37,
/// SCRUM-272).
///
/// No salen del prototipo: se definieron con el equipo en el planning. Van
/// de la más corta a la más larga, que es como se leen en la fila.
///
/// Cada distancia cae en uno solo (SCRUM-274): 5 km ya no es "Menos de 5
/// km" sino "5 a 10 km", 10 km es "5 a 10 km" y 20 km, "10 a 20 km". Así
/// una ruta no sale repetida al pasar de un rango al de al lado.
enum RangoDistancia {
  menosDe5('Menos de 5 km'),
  de5a10('5 a 10 km'),
  de10a20('10 a 20 km'),
  masDe20('Más de 20 km');

  const RangoDistancia(this.etiqueta);

  /// Lo que dice su chip.
  final String etiqueta;

  /// El rango de una ruta que mide [km].
  ///
  /// Se mira la distancia como la muestra la tarjeta, en centésimas
  /// (`TarjetaReto.textoKm`), y no como la guarda la base, con todos sus
  /// decimales: una ruta de 4,996 km se ve como "5 km", y quien elige "5 a 10
  /// km" espera encontrarla ahí.
  static RangoDistancia de(double km) {
    final comoSeVe = double.parse(km.toStringAsFixed(2));
    if (comoSeVe < 5) return menosDe5;
    if (comoSeVe <= 10) return de5a10;
    if (comoSeVe <= 20) return de10a20;
    return masDe20;
  }

  /// Si una ruta que mide [km] entra en este rango. Una sin distancia
  /// registrada no entra en ninguno: no se sabe cuánto mide.
  bool contiene(double? km) => km != null && de(km) == this;
}
