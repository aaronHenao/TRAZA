import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/ruta_oficial.dart';

/// Pruebas de una ruta oficial: su posición en el camino y la ruta publicada
/// a la que apunta (rutas oficiales, etapa 1).
void main() {
  // La ruta como la embebe la consulta de `rutas_oficiales`: las columnas
  // del listado de `rutas`.
  Map<String, dynamic> filaRuta({
    String id = 'ruta-1',
    String nombre = 'Vuelta al estadio',
    Object? dificultad = 'moderada',
  }) => {
    'id': id,
    'autor_id': 'usuario-1',
    'autor_nombre': 'Ana',
    'entrenamiento_id': 'entrenamiento-1',
    'nombre': nombre,
    'descripcion': null,
    'distancia_km': 5.23,
    'estado': 'publicada',
    'motivo_rechazo': null,
    'fecha_creacion': '2026-10-17T14:00:00+00:00',
    'fecha_publicacion': '2026-10-18T09:00:00+00:00',
    'dificultad': dificultad,
  };

  // Una fila de `rutas_oficiales` con su ruta embebida.
  Map<String, dynamic> fila({Object? posicion = 1, Object? ruta}) => {
    'posicion': posicion,
    'ruta': ruta ?? filaRuta(),
  };

  group('desdeSupabase', () {
    test('lee la posición y la ruta con su nombre, autor, distancia y '
        'dificultad (criterio 2)', () {
      final oficial = RutaOficial.desdeSupabase(fila(posicion: 3));

      expect(oficial.posicion, 3);
      expect(oficial.ruta.id, 'ruta-1');
      expect(oficial.ruta.nombre, 'Vuelta al estadio');
      expect(oficial.ruta.autorNombre, 'Ana');
      expect(oficial.ruta.distanciaKm, 5.23);
      expect(oficial.ruta.dificultad, Dificultad.moderada);
      expect(oficial.ruta.estado, EstadoRuta.publicada);
    });

    test('una ruta que todavía no tiene dificultad se lee con la dificultad '
        'en null (criterio 2)', () {
      final oficial = RutaOficial.desdeSupabase(
        fila(ruta: filaRuta(dificultad: null)),
      );

      expect(oficial.ruta.dificultad, isNull);
    });

    test('una fila sin posición no se acepta', () {
      // La columna es `not null`: si falta, la consulta y la clase se
      // desalinearon, y eso se arregla, no se disimula con un cero.
      expect(
        () => RutaOficial.desdeSupabase(fila(posicion: null)),
        throwsFormatException,
      );
    });

    test('una posición que no es un entero no se acepta', () {
      expect(
        () => RutaOficial.desdeSupabase(fila(posicion: 'primera')),
        throwsFormatException,
      );
    });

    test('una fila sin la ruta embebida no se acepta', () {
      expect(
        () => RutaOficial.desdeSupabase({'posicion': 1, 'ruta': null}),
        throwsFormatException,
      );
      expect(
        () => RutaOficial.desdeSupabase({'posicion': 1}),
        throwsFormatException,
      );
    });
  });

  group('igualdad', () {
    test('dos con la misma posición y la misma ruta son iguales', () {
      final una = RutaOficial.desdeSupabase(fila());
      final otra = RutaOficial.desdeSupabase(fila());

      expect(una, otra);
      expect(una.hashCode, otra.hashCode);
    });

    test('la ruta se compara por su id, no por el resto de sus datos', () {
      final una = RutaOficial.desdeSupabase(fila());
      final renombrada = RutaOficial.desdeSupabase(
        fila(ruta: filaRuta(nombre: 'Otro nombre')),
      );

      expect(una, renombrada);
      expect(una.hashCode, renombrada.hashCode);
    });

    test('la misma ruta en otra posición no es igual: al moverla, la lista '
        'cambia', () {
      expect(
        RutaOficial.desdeSupabase(fila(posicion: 1)),
        isNot(RutaOficial.desdeSupabase(fila(posicion: 2))),
      );
    });

    test('otra ruta en la misma posición no es igual', () {
      expect(
        RutaOficial.desdeSupabase(fila()),
        isNot(RutaOficial.desdeSupabase(fila(ruta: filaRuta(id: 'ruta-2')))),
      );
    });
  });
}
