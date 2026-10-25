import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/ruta.dart';

/// Validación de una ruta antes de enviarla (criterio 3 de SCRUM-241),
/// conversión del recorrido de un entrenamiento en su trazado y lectura de
/// las filas de `rutas`.
///
/// SCRUM-363 agrega quién puede clasificar una ruta y quién confirmar su
/// publicación.
void main() {
  PuntoGps punto(double lat, double lng) => PuntoGps(
    latitud: lat,
    longitud: lng,
    capturadoEn: DateTime(2026, 10, 17, 7),
  );

  final recorrido = [punto(6.2442, -75.5812), punto(6.2450, -75.5800)];

  BorradorRuta borrador({
    String nombre = 'Vuelta al estadio',
    String descripcion = '',
    List<PuntoGps>? puntos,
  }) => BorradorRuta(
    entrenamientoId: 'entrenamiento-1',
    puntos: puntos ?? recorrido,
    nombre: nombre,
    descripcion: descripcion,
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

  group('BorradorRuta.errores', () {
    test('con nombre y recorrido no tiene nada que corregir', () {
      expect(borrador().errores, isEmpty);
      expect(borrador().esValido, isTrue);
    });

    test('sin nombre lo señala y no deja crear la ruta', () {
      final sinNombre = borrador(nombre: '   ');

      expect(sinNombre.errores, {
        CampoRuta.nombre: 'Ponle un nombre a tu ruta.',
      });
      expect(sinNombre.aNuevaRuta(), isNull);
    });

    test('acepta el nombre justo en el limite y rechaza uno mas', () {
      final justo = borrador(nombre: 'a' * maxCaracteresNombreRuta);
      final pasado = borrador(nombre: 'a' * (maxCaracteresNombreRuta + 1));

      expect(justo.errores, isEmpty);
      expect(pasado.errores.keys, [CampoRuta.nombre]);
    });

    test('una descripcion demasiado larga se señala aparte', () {
      final largo = borrador(
        descripcion: 'a' * (maxCaracteresDescripcionRuta + 1),
      );

      expect(largo.errores.keys, [CampoRuta.descripcion]);
    });

    test('un entrenamiento sin recorrido no se puede publicar', () {
      final sinPuntos = borrador(puntos: const []);
      final unPunto = borrador(puntos: [punto(6.2442, -75.5812)]);

      expect(sinPuntos.errores, {
        CampoRuta.trazado:
            'Este entrenamiento no tiene un recorrido que publicar.',
      });
      expect(unPunto.errores.keys, [CampoRuta.trazado]);
    });

    test('un entrenamiento quieto tampoco es un recorrido', () {
      // El GPS encendido con el corredor sin moverse: hay puntos, pero
      // todos en la misma coordenada.
      final quieto = borrador(
        puntos: [
          punto(6.2442, -75.5812),
          punto(6.2442, -75.5812),
          punto(6.2442, -75.5812),
        ],
      );

      expect(quieto.errores.keys, [CampoRuta.trazado]);
    });

    test('señala a la vez todo lo que falta', () {
      final vacio = borrador(nombre: '', puntos: const []);

      expect(
        vacio.errores.keys,
        containsAll([CampoRuta.nombre, CampoRuta.trazado]),
      );
    });
  });

  group('BorradorRuta.aNuevaRuta', () {
    test('convierte los puntos del entrenamiento en trazado, en orden', () {
      final nueva = borrador().aNuevaRuta()!;

      expect(nueva.trazado, [
        const PuntoRuta(latitud: 6.2442, longitud: -75.5812),
        const PuntoRuta(latitud: 6.2450, longitud: -75.5800),
      ]);
    });

    test('manda lo del cliente y nada de lo que pone la base', () {
      final nueva = borrador(
        descripcion: '  Plana y con sombra  ',
      ).aNuevaRuta()!;

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

    test('sin descripcion no se manda la clave', () {
      final nueva = borrador(descripcion: '   ').aNuevaRuta()!;

      expect(nueva.aSupabase().containsKey('descripcion'), isFalse);
    });

    test('un recorrido corto se guarda entero', () {
      final nueva = borrador(
        puntos: [
          for (var i = 0; i < maxPuntosTrazadoRuta; i++)
            punto(6.24 + i / 10000, -75.58),
        ],
      ).aNuevaRuta()!;

      expect(nueva.trazado.length, maxPuntosTrazadoRuta);
    });

    test('un recorrido largo se recorta conservando inicio y fin', () {
      // Una hora de carrera con un punto cada 5 m deja miles; guardarlos
      // todos no mejora el camino que se sigue y pesa en cada consulta.
      final puntos = [
        for (var i = 0; i < 3000; i++) punto(6.24 + i / 10000, -75.58),
      ];

      final nueva = borrador(puntos: puntos).aNuevaRuta()!;

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

    test('lee los estados nuevos de la clasificacion, con los nombres de '
        '0045 (SCRUM-363)', () {
      expect(EstadoRuta.clasificada.valorDb, 'clasificada');
      expect(EstadoRuta.datosIncompletos.valorDb, 'datos_incompletos');
      expect(EstadoRuta.desdeDb('clasificada'), EstadoRuta.clasificada);
      expect(
        EstadoRuta.desdeDb('datos_incompletos'),
        EstadoRuta.datosIncompletos,
      );
    });
  });

  group('la clasificacion de una ruta (SCRUM-363)', () {
    Ruta ruta({
      EstadoRuta estado = EstadoRuta.enRevision,
      Dificultad? dificultad,
    }) => Ruta(
      id: 'ruta-1',
      autorId: 'autor-1',
      autorNombre: 'María',
      nombre: 'Cerro Pan de Azúcar',
      estado: estado,
      distanciaKm: 5.23,
      dificultad: dificultad,
      fechaCreacion: DateTime(2026, 10, 17, 9),
    );

    test('Ruta.desdeSupabase lee una ruta clasificada con su dificultad '
        '(criterio 2 de SCRUM-363)', () {
      final leida = Ruta.desdeSupabase({
        ...fila(estado: 'clasificada', distancia: 5.23),
        'dificultad': 'moderada',
      });

      expect(leida.estado, EstadoRuta.clasificada);
      expect(leida.dificultad, Dificultad.moderada);
      expect(leida.publicada, isFalse);
    });

    test('Ruta.desdeSupabase lee una ruta con la dificultad pendiente '
        '(criterio 3 de SCRUM-363)', () {
      final leida = Ruta.desdeSupabase({
        ...fila(estado: 'datos_incompletos'),
        'dificultad': null,
      });

      expect(leida.estado, EstadoRuta.datosIncompletos);
      expect(leida.dificultad, isNull);
      expect(leida.tieneDistancia, isFalse);
    });

    group('clasificablePor', () {
      test('un Runner Experto puede clasificar la ruta ajena que esta en '
          'revision (criterio 1 de SCRUM-363)', () {
        expect(ruta().clasificablePor('experto-1', esExperto: true), isTrue);
      });

      test('un experto no clasifica su propia ruta', () {
        expect(ruta().clasificablePor('autor-1', esExperto: true), isFalse);
      });

      test('un corredor que no es experto no clasifica', () {
        expect(ruta().clasificablePor('otro-1', esExperto: false), isFalse);
      });

      test('sin sesion no se clasifica', () {
        expect(ruta().clasificablePor(null, esExperto: true), isFalse);
      });

      test('solo lo que esta en revision: ni la ya clasificada, ni la '
          'publicada, ni la rechazada, ni la que tiene la dificultad '
          'pendiente (criterio 3 de SCRUM-363)', () {
        for (final estado in [
          EstadoRuta.clasificada,
          EstadoRuta.publicada,
          EstadoRuta.rechazada,
          EstadoRuta.datosIncompletos,
        ]) {
          expect(
            ruta(
              estado: estado,
              dificultad: Dificultad.facil,
            ).clasificablePor('experto-1', esExperto: true),
            isFalse,
            reason: '$estado',
          );
        }
      });
    });

    group('publicablePor', () {
      test('el autor puede confirmar la ruta que el experto ya clasifico '
          '(criterio 2 de SCRUM-363)', () {
        final clasificada = ruta(
          estado: EstadoRuta.clasificada,
          dificultad: Dificultad.moderada,
        );

        expect(clasificada.publicablePor('autor-1'), isTrue);
      });

      test('sin la dificultad asignada el autor no la publica: en revision, '
          'con la dificultad pendiente, ya publicada o rechazada', () {
        for (final estado in [
          EstadoRuta.enRevision,
          EstadoRuta.datosIncompletos,
          EstadoRuta.publicada,
          EstadoRuta.rechazada,
        ]) {
          expect(
            ruta(estado: estado).publicablePor('autor-1'),
            isFalse,
            reason: '$estado',
          );
        }
      });

      test('nadie mas que el autor la publica, ni el experto', () {
        final clasificada = ruta(
          estado: EstadoRuta.clasificada,
          dificultad: Dificultad.moderada,
        );

        expect(clasificada.publicablePor('experto-1'), isFalse);
        expect(clasificada.publicablePor(null), isFalse);
      });
    });
  });
}
