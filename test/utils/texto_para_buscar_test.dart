import 'package:flutter_test/flutter_test.dart';
import 'package:traza/utils/texto_para_buscar.dart';

/// Pruebas de cómo se normaliza un texto para buscar (SCRUM-256).
///
/// Los casos son los mismos con que se probó `texto_para_buscar` de la
/// base (0041): la app y la base tienen que dar lo mismo.
void main() {
  test('quita tildes, mayúsculas y espacios de más', () {
    expect(textoParaBuscar('  Ciclovía   del RÍO  '), 'ciclovia del rio');
  });

  test('lo que no es letra ni número separa palabras', () {
    expect(
      textoParaBuscar('Vuelta (Laureles-Estadio), 100%'),
      'vuelta laureles estadio 100',
    );
  });

  test('la ñ es una n, en mayúscula y en minúscula', () {
    expect(textoParaBuscar('PEÑA'), 'pena');
    expect(textoParaBuscar('Peña'), 'pena');
  });

  test('la diéresis y las demás tildes también', () {
    expect(
      textoParaBuscar('Pingüino Güí Àlvarez Çà'),
      'pinguino gui alvarez ca',
    );
  });

  test('sin letras ni números queda vacío', () {
    expect(textoParaBuscar('__ %% --'), '');
    expect(textoParaBuscar(''), '');
  });
}
