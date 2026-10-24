/// Un texto como lo compara la búsqueda de rutas: sin tildes, en
/// minúsculas, la ñ como n, y solo letras y números separados por un
/// espacio (SCRUM-256).
///
/// Es la misma cuenta que hace `texto_para_buscar` en la base (0041), con
/// las mismas letras: así la app sabe, antes de preguntar, si lo escrito
/// alcanza para buscar, y el buscador de zonas compara nombres igual que la
/// base compara rutas. Si cambia allá, cambia aquí.
String textoParaBuscar(String texto) {
  final sinTildes = StringBuffer();
  for (final letra in texto.split('')) {
    sinTildes.write(_sinTilde[letra] ?? letra);
  }
  return sinTildes
      .toString()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .trim();
}

/// El `translate` de la base, letra por letra.
const _sinTilde = {
  'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A', 'Ã': 'A', //
  'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E', //
  'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I', //
  'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O', 'Õ': 'O', //
  'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U', //
  'Ñ': 'N', 'Ç': 'C', //
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', //
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o', //
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', //
  'ñ': 'n', 'ç': 'c',
};
