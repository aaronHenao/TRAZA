/// La dificultad de una ruta: los tres niveles por los que se filtran las
/// rutas (criterio 1 de HU-36).
///
/// La asigna un Runner Experto antes de publicar la ruta (SCRUM-363). Una
/// ruta que todavía no la tiene va "Sin clasificar". La app la lee, la
/// muestra y filtra por ella (SCRUM-275).
///
/// En la base va en `rutas.dificultad`, como [valorDb]: los mismos valores
/// que admite `rutas_dificultad_valida` (0045).
enum Dificultad {
  facil('facil', 'Fácil', 'fáciles'),
  moderada('moderada', 'Moderada', 'moderadas'),
  dificil('dificil', 'Difícil', 'difíciles');

  const Dificultad(this.valorDb, this.etiqueta, this.plural);

  final String valorDb;

  /// Como se escribe sola: en la pastilla de la tarjeta y en su chip.
  final String etiqueta;

  /// Como se dice de varias rutas: "rutas fáciles".
  final String plural;

  /// La de `rutas.dificultad`, o null si la ruta no tiene.
  ///
  /// Un valor que no se conoce se lee como sin clasificar, en vez de
  /// reventar la lista entera por una ruta.
  static Dificultad? desdeDb(Object? valor) {
    for (final dificultad in values) {
      if (dificultad.valorDb == valor) return dificultad;
    }
    return null;
  }
}
