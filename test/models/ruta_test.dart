import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/ruta.dart';

/// Conversión del recorrido de un entrenamiento en el trazado de una ruta
/// (SCRUM-241) y lectura de las filas de `rutas`.
void main() {
  PuntoGps punto(double lat, double lng) => PuntoGps(
    latitud: lat,
    longitud: lng,
    capturadoEn: DateTime(2026, 10, 17, 7),
  );

  Map<String, dynamic> fila({
    String estado = 'en_revision',
    Object? distancia,
    Object? trazado,
    Object? fechaPublicacion,
    Object? descripcion,
    Object? entrenamiento = 'entrenamiento-1',
    Object? motivo,
  }) => {
    'id': 'ruta-1',
    'autor_id': 'corredor-1',
    'autor_nombre': 'María',
    'entrenamiento_id': entrenamiento,
    'nombre': 'Cerro Pan de Azúcar',
    'descripcion': descripcion,
    'trazado': trazado,
    'distancia_km': distancia,
    'estado': estado,
    'motivo_rechazo': motivo,
    'fecha_creacion': '2026-10-17T12:00:00Z',
    'fecha_publicacion': fechaPublicacion,
  };

  group('NuevaRuta.desdeRecorrido', () {
    test('convierte los puntos del entrenamiento en trazado, en orden', () {
      final nueva = NuevaRuta.desdeRecorrido(
        entrenamientoId: 'entrenamiento-1',
        nombre: 'Vuelta al estadio',
        puntos: [punto(6.2442, -75.5812), punto(6.2450, -75.5800)],
      );

      expect(nueva.trazado, [
        const PuntoRuta(latitud: 6.2442, longitud: -75.5812),
        const PuntoRuta(latitud: 6.2450, longitud: -75.5800),
      ]);
    });

    test('un recorrido corto se guarda entero', () {
      final puntos = [
        for (var i = 0; i < maxPuntosTrazadoRuta; i++)
          punto(6.24 + i / 10000, -75.58),
      ];

      final nueva = NuevaRuta.desdeRecorrido(
        entrenamientoId: 'entrenamiento-1',
        nombre: 'Justo en el límite',
        puntos: puntos,
      );

      expect(nueva.trazado.length, maxPuntosTrazadoRuta);
    });

    test('un recorrido largo se recorta conservando inicio y fin', () {
      // Una hora de carrera con un punto cada 5 m deja miles; guardarlos
      // todos no mejora el camino que se sigue y pesa en cada consulta.
      final puntos = [
        for (var i = 0; i < 3000; i++) punto(6.24 + i / 10000, -75.58),
      ];

      final nueva = NuevaRuta.desdeRecorrido(
        entrenamientoId: 'entrenamiento-1',
        nombre: 'Maratón',
        puntos: puntos,
      );

      expect(nueva.trazado.length, maxPuntosTrazadoRuta);
      // El primero importa: es el que la base guarda como inicio de la ruta.
      expect(nueva.trazado.first.latitud, 6.24);
      expect(nueva.trazado.last.latitud, puntos.last.latitud);
    });

    test('el recorte reparte los puntos a lo largo del recorrido', () {
      final puntos = [for (var i = 0; i < 100; i++) punto(i.toDouble(), 0)];

      final trazado = NuevaRuta.trazadoDesdePuntos(puntos, maximo: 10);

      expect(trazado.length, 10);
      expect(trazado.first.latitud, 0);
      expect(trazado.last.latitud, 99);
      // Repartidos, no los diez primeros.
      expect(trazado[1].latitud, greaterThan(5));
    });
  });

  group('NuevaRuta.aSupabase', () {
    test('manda lo del cliente y nada de lo que pone la base', () {
      final nueva = NuevaRuta.desdeRecorrido(
        entrenamientoId: 'entrenamiento-1',
        nombre: 'Vuelta al estadio',
        descripcion: '  Plana y con sombra  ',
        puntos: [punto(6.2442, -75.5812), punto(6.2450, -75.5800)],
      );

      expect(nueva.aSupabase(), {
        'entrenamiento_id': 'entrenamiento-1',
        'nombre': 'Vuelta al estadio',
        'descripcion': 'Plana y con sombra',
        'trazado': [
          {'lat': 6.2442, 'lng': -75.5812},
          {'lat': 6.2450, 'lng': -75.5800},
        ],
      });
    });

    test('una descripcion en blanco no se manda', () {
      final nueva = NuevaRuta.desdeRecorrido(
        entrenamientoId: 'entrenamiento-1',
        nombre: 'Sin descripción',
        descripcion: '   ',
        puntos: [punto(6.2442, -75.5812), punto(6.2450, -75.5800)],
      );

      expect(nueva.aSupabase().containsKey('descripcion'), isFalse);
    });
  });

  group('Ruta.desdeSupabase', () {
    test('lee la fila que devuelve el insert', () {
      final ruta = Ruta.desdeSupabase(
        fila(
          distancia: 10.25,
          descripcion: 'Ascenso exigente',
          trazado: [
            {'lat': 6.2442, 'lng': -75.5812},
            {'lat': 6.2450, 'lng': -75.5800},
          ],
        ),
      );

      expect(ruta.id, 'ruta-1');
      expect(ruta.autorNombre, 'María');
      expect(ruta.estado, EstadoRuta.enRevision);
      expect(ruta.publicada, isFalse);
      expect(ruta.distanciaKm, 10.25);
      expect(ruta.tieneDistancia, isTrue);
      expect(ruta.trazado.length, 2);
      expect(ruta.descripcion, 'Ascenso exigente');
      expect(ruta.fechaPublicacion, isNull);
    });

    test('una ruta publicada trae su fecha de publicacion', () {
      final ruta = Ruta.desdeSupabase(
        fila(estado: 'publicada', fechaPublicacion: '2026-10-18T15:00:00Z'),
      );

      expect(ruta.publicada, isTrue);
      expect(ruta.fechaPublicacion, isNotNull);
    });

    test('sin distancia registrada no revienta: lo dice (SCRUM-240)', () {
      final ruta = Ruta.desdeSupabase(fila());

      expect(ruta.distanciaKm, isNull);
      expect(ruta.tieneDistancia, isFalse);
    });

    test('la distancia tambien llega como texto', () {
      // `numeric` viaja como número o como cadena según el caso, igual que
      // `distancia_total_m` en los entrenamientos.
      final ruta = Ruta.desdeSupabase(fila(distancia: '7.50'));

      expect(ruta.distanciaKm, 7.5);
    });

    test('un listado sin trazado deja el trazado vacio', () {
      final ruta = Ruta.desdeSupabase(fila());

      expect(ruta.trazado, isEmpty);
    });

    test('descarta los puntos del trazado sin coordenadas', () {
      final ruta = Ruta.desdeSupabase(
        fila(
          trazado: [
            {'lat': 6.2442, 'lng': -75.5812},
            {'lat': 6.2450},
            'esto no es un punto',
          ],
        ),
      );

      expect(ruta.trazado, [
        const PuntoRuta(latitud: 6.2442, longitud: -75.5812),
      ]);
    });

    test('una ruta sin entrenamiento sigue siendo legible', () {
      // Su autor borró el entrenamiento del que nació; la ruta no se va con
      // él porque la comunidad ya la usa.
      final ruta = Ruta.desdeSupabase(fila(entrenamiento: null));

      expect(ruta.entrenamientoId, isNull);
    });

    test('un estado que no existe no pasa por legible', () {
      expect(
        () => Ruta.desdeSupabase(fila(estado: 'archivada')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('EstadoRuta', () {
    test('los nombres son los de la restriccion de la tabla', () {
      expect(EstadoRuta.desdeDb('en_revision'), EstadoRuta.enRevision);
      expect(EstadoRuta.desdeDb('publicada'), EstadoRuta.publicada);
      expect(EstadoRuta.desdeDb('rechazada'), EstadoRuta.rechazada);
      expect(EstadoRuta.desdeDb('retirada'), isNull);
    });
  });
}
