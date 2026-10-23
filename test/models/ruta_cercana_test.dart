import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_cercana.dart';

/// Pruebas de la ruta con su distancia al usuario (SCRUM-246).
void main() {
  // Una fila de `rutas_cercanas` (0037): las columnas del listado, sin el
  // trazado, más la distancia al usuario.
  Map<String, dynamic> fila({Object? distanciaUsuario = 2.37}) => {
    'id': 'ruta-1',
    'autor_id': 'usuario-1',
    'autor_nombre': 'Ana',
    'entrenamiento_id': 'entrenamiento-1',
    'nombre': 'Vuelta al estadio',
    'descripcion': null,
    'distancia_km': 5.23,
    'estado': 'publicada',
    'motivo_rechazo': null,
    'fecha_creacion': '2026-10-17T14:00:00+00:00',
    'fecha_publicacion': '2026-10-18T09:00:00+00:00',
    'distancia_usuario_km': distanciaUsuario,
  };

  test('lee la ruta y a cuántos km le queda al usuario', () {
    final cercana = RutaCercana.desdeSupabase(fila());

    expect(cercana.ruta.id, 'ruta-1');
    expect(cercana.ruta.nombre, 'Vuelta al estadio');
    expect(cercana.ruta.autorNombre, 'Ana');
    expect(cercana.ruta.estado, EstadoRuta.publicada);
    expect(cercana.distanciaKm, 2.37);
  });

  test('no confunde lo que mide la ruta con lo que le queda al usuario', () {
    final cercana = RutaCercana.desdeSupabase(fila());

    // 5.23 km de recorrido, que arranca a 2.37 km del usuario.
    expect(cercana.ruta.distanciaKm, 5.23);
    expect(cercana.distanciaKm, 2.37);
  });

  test('trae la miniatura del recorrido (SCRUM-247)', () {
    final cercana = RutaCercana.desdeSupabase({
      ...fila(),
      'miniatura': [
        {'lat': 6.2566, 'lng': -75.5900},
        {'lat': 6.2580, 'lng': -75.5885},
        {'lat': 6.2566, 'lng': -75.5870},
      ],
    });

    expect(cercana.ruta.miniatura, const [
      PuntoRuta(latitud: 6.2566, longitud: -75.5900),
      PuntoRuta(latitud: 6.2580, longitud: -75.5885),
      PuntoRuta(latitud: 6.2566, longitud: -75.5870),
    ]);
  });

  test('sin miniatura, la ruta se lee igual', () {
    // Una consulta que no la pidió: la tarjeta pone el icono de ruta.
    expect(RutaCercana.desdeSupabase(fila()).ruta.miniatura, isEmpty);
  });

  test('una distancia entera también se lee', () {
    expect(RutaCercana.desdeSupabase(fila(distanciaUsuario: 3)).distanciaKm, 3);
  });

  test('una fila sin distancia al usuario no se acepta', () {
    // La función siempre la devuelve: si falta, la consulta y la clase se
    // desalinearon, y eso se arregla, no se disimula con un cero.
    expect(
      () => RutaCercana.desdeSupabase(fila(distanciaUsuario: null)),
      throwsFormatException,
    );
  });

  test('dos con la misma ruta y la misma distancia son iguales', () {
    final una = RutaCercana.desdeSupabase(fila());
    final otra = RutaCercana.desdeSupabase(fila());

    expect(una, otra);
    // Y dan el mismo hash: si no, un Set o un Map las tomarían por distintas
    // (SCRUM-251).
    expect(una.hashCode, otra.hashCode);
  });

  test('la misma ruta a otra distancia ya no es la misma (SCRUM-251)', () {
    expect(
      RutaCercana.desdeSupabase(fila()),
      isNot(RutaCercana.desdeSupabase(fila(distanciaUsuario: 9.9))),
    );
  });
}
