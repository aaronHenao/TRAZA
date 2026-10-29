import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/calculadora_distancia.dart';

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

  /// Un paso de latitud ≈ 11,1 m, que es el orden de una lectura del GPS.
  const paso = 1 / 10000;

  /// Un recorrido recto de ~1,1 km. Tiene que ser bastante más largo que los
  /// dos radios de privacidad (RNF-04), o no quedaría trazo que publicar.
  final recorrido = [
    for (var i = 0; i <= 100; i++) punto(6.2442 + i * paso, -75.5812),
  ];

  BorradorRuta borrador({
    String nombre = 'Vuelta al estadio',
    String descripcion = '',
    List<PuntoGps>? puntos,
    bool recorridoCompleto = false,
  }) => BorradorRuta(
    entrenamientoId: 'entrenamiento-1',
    puntos: puntos ?? recorrido,
    nombre: nombre,
    descripcion: descripcion,
    recorridoCompleto: recorridoCompleto,
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

      // Sin los extremos privados (RNF-04), pero en el mismo orden y sobre
      // la misma recta que el recorrido.
      expect(nueva.trazado.length, lessThan(recorrido.length));
      expect(
        nueva.trazado.map((p) => p.latitud).toList(),
        orderedEquals([...nueva.trazado.map((p) => p.latitud)]..sort()),
      );
      expect(nueva.trazado.every((p) => p.longitud == -75.5812), isTrue);
    });

    test('manda lo del cliente y nada de lo que pone la base', () {
      final nueva = borrador(
        descripcion: '  Plana y con sombra  ',
      ).aNuevaRuta()!;

      final enviado = nueva.aSupabase();

      expect(enviado['entrenamiento_id'], 'entrenamiento-1');
      expect(enviado['nombre'], 'Vuelta al estadio');
      expect(enviado['descripcion'], 'Plana y con sombra');
      // Nada de autor, estado, inicio, distancia ni fechas: los pone la base.
      expect(enviado.keys, hasLength(5));
      expect(enviado['recorrido_completo'], false);
      expect(enviado['trazado'], isA<List<Map<String, double>>>());
    });

    test('sin descripcion no se manda la clave', () {
      final nueva = borrador(descripcion: '   ').aNuevaRuta()!;

      expect(nueva.aSupabase().containsKey('descripcion'), isFalse);
    });

    test('un recorrido que cabe en el tope se guarda sin repartir', () {
      // Lo bastante largo para que, tras quitar los extremos privados,
      // queden menos puntos que el tope.
      final nueva = borrador(
        puntos: [for (var i = 0; i < 400; i++) punto(6.24 + i * paso, -75.58)],
      ).aNuevaRuta()!;

      // 400 puntos menos los ~18 de cada extremo que caen dentro de 200 m.
      expect(nueva.trazado.length, lessThan(400));
      expect(nueva.trazado.length, greaterThan(300));
    });

    test('un recorrido largo se recorta al tope de puntos', () {
      // Una hora de carrera con un punto cada 5 m deja miles; guardarlos
      // todos no mejora el camino que se sigue y pesa en cada consulta.
      final puntos = [
        for (var i = 0; i < 3000; i++) punto(6.24 + i * paso, -75.58),
      ];

      final nueva = borrador(puntos: puntos).aNuevaRuta()!;

      expect(nueva.trazado.length, maxPuntosTrazadoRuta);
    });

    test('el recorte reparte los puntos a lo largo del recorrido', () {
      // Separados un grado (~111 km): el radio de privacidad solo alcanza a
      // los dos extremos, así que esta prueba mide el reparto del resto.
      final puntos = [for (var i = 0; i < 100; i++) punto(i.toDouble(), 0)];

      final trazado = NuevaRuta.trazadoDesdePuntos(puntos, maximo: 10);

      expect(trazado.length, 10);
      expect(trazado.first.latitud, 1);
      expect(trazado.last.latitud, 98);
      // Repartidos, no los diez primeros.
      expect(trazado[1].latitud, greaterThan(5));
    });
  });

  group('privacidad de los extremos (RNF-04)', () {
    test('el trazado publicado no empieza ni acaba donde el recorrido', () {
      final puntos = [
        for (var i = 0; i <= 200; i++) punto(6.2442 + i * paso, -75.5812),
      ];

      final trazado = NuevaRuta.trazadoDesdePuntos(puntos);

      expect(trazado.first.latitud, isNot(puntos.first.latitud));
      expect(trazado.last.latitud, isNot(puntos.last.latitud));
    });

    test('lo que se quita es al menos el radio, por los dos lados', () {
      final puntos = [
        for (var i = 0; i <= 200; i++) punto(6.2442 + i * paso, -75.5812),
      ];

      final trazado = NuevaRuta.trazadoDesdePuntos(puntos);

      double desde(PuntoGps origen, PuntoRuta otro) =>
          CalculadoraDistancia.haversineMetros(
            origen.latitud,
            origen.longitud,
            otro.latitud,
            otro.longitud,
          );

      expect(
        desde(puntos.first, trazado.first),
        greaterThanOrEqualTo(radioPrivacidadMetros),
      );
      expect(
        desde(puntos.last, trazado.last),
        greaterThanOrEqualTo(radioPrivacidadMetros),
      );
    });

    test('el medio del recorrido se conserva entero', () {
      final puntos = [
        for (var i = 0; i <= 200; i++) punto(6.2442 + i * paso, -75.5812),
      ];

      final trazado = NuevaRuta.trazadoDesdePuntos(puntos);

      // 200 pasos de 11 m son ~2,2 km; quitando 200 m por lado queda la
      // mayor parte.
      expect(trazado.length, greaterThan(140));
    });

    test('dar vueltas cerca del inicio no deja un trozo pegado a él', () {
      // Sale, vuelve casi al punto de partida y después se aleja de verdad.
      final puntos = [
        for (var i = 0; i <= 10; i++) punto(6.2442 + i * paso, -75.5812),
        for (var i = 10; i >= 0; i--) punto(6.2442 + i * paso, -75.5812),
        for (var i = 0; i <= 100; i++) punto(6.2442 + i * paso, -75.5812),
      ];

      final trazado = NuevaRuta.trazadoDesdePuntos(puntos);

      // El radio se mide contra el punto de partida, no contra el anterior:
      // la ida y vuelta de los primeros 110 m no aparece.
      for (final punto in trazado) {
        expect(
          CalculadoraDistancia.haversineMetros(
            6.2442,
            -75.5812,
            punto.latitud,
            punto.longitud,
          ),
          greaterThanOrEqualTo(radioPrivacidadMetros),
        );
      }
    });

    test('un recorrido más corto que los dos radios no se puede publicar', () {
      // ~330 m: todo él cae dentro de los dos círculos.
      final corto = borrador(
        puntos: [
          for (var i = 0; i <= 30; i++) punto(6.2442 + i * paso, -75.58),
        ],
      );

      expect(corto.esValido, isFalse);
      expect(corto.aNuevaRuta(), isNull);
      final error = corto.errores[CampoRuta.trazado]!;
      expect(error, contains('privacidad'));
      // Dice qué hacer, no solo que no se puede.
      expect(error, contains('más largo'));
    });

    test('con el recorrido completo no se recorta nada', () {
      final nueva = borrador(recorridoCompleto: true).aNuevaRuta()!;

      expect(nueva.trazado.length, recorrido.length);
      expect(nueva.trazado.first.latitud, recorrido.first.latitud);
      expect(nueva.trazado.last.latitud, recorrido.last.latitud);
      expect(nueva.recorridoCompleto, isTrue);
    });

    test('se le dice a la base cómo se publicó', () {
      expect(borrador().aNuevaRuta()!.aSupabase()['recorrido_completo'], false);
      expect(
        borrador(
          recorridoCompleto: true,
        ).aNuevaRuta()!.aSupabase()['recorrido_completo'],
        true,
      );
    });

    test('una ruta corta sí se puede publicar entera', () {
      final puntos = [
        for (var i = 0; i <= 30; i++) punto(6.2442 + i * paso, -75.58),
      ];

      // Recortada no cabe; entera sí, porque no se le quita nada.
      expect(borrador(puntos: puntos).esValido, isFalse);
      expect(
        borrador(puntos: puntos, recorridoCompleto: true).esValido,
        isTrue,
      );
    });

    test('lo que no consta no es lo mismo que recortado', () {
      // Las rutas anteriores a RNF-04 y las que vienen de los listados no
      // traen la columna: no afirman nada.
      expect(Ruta.desdeSupabase(fila()).recorridoCompleto, isNull);
      expect(Ruta.desdeSupabase(fila()).trazoRecortado, isFalse);

      expect(
        Ruta.desdeSupabase({
          ...fila(),
          'recorrido_completo': false,
        }).trazoRecortado,
        isTrue,
      );
      expect(
        Ruta.desdeSupabase({
          ...fila(),
          'recorrido_completo': true,
        }).trazoRecortado,
        isFalse,
      );
    });

    test('con el radio en cero no se recorta nada', () {
      final puntos = [
        for (var i = 0; i <= 10; i++) punto(6.2442 + i * paso, -75.58),
      ];

      final trazado = NuevaRuta.trazadoDesdePuntos(puntos, radioPrivacidad: 0);

      expect(trazado.length, puntos.length);
      expect(trazado.first.latitud, puntos.first.latitud);
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

    test('lee la etapa del Runner Experto con el nombre de 0048 '
        '(SCRUM-321 + SCRUM-363)', () {
      expect(EstadoRuta.revisionExperto.valorDb, 'revision_experto');
      expect(
        EstadoRuta.desdeDb('revision_experto'),
        EstadoRuta.revisionExperto,
      );
    });

    test('la etiqueta dice a quien espera la ruta: primero al '
        'administrador y despues al Runner Experto (SCRUM-321)', () {
      expect(
        EstadoRuta.enRevision.etiqueta,
        'Pendiente de revisión del administrador',
      );
      expect(
        EstadoRuta.revisionExperto.etiqueta,
        'Pendiente de revisión del Runner Experto',
      );
    });
  });

  group('la clasificacion de una ruta (SCRUM-363)', () {
    Ruta ruta({
      EstadoRuta estado = EstadoRuta.revisionExperto,
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
      test('un Runner Experto puede clasificar la ruta ajena que el '
          'administrador ya aprobo (criterio 1 de SCRUM-363)', () {
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

      test('solo lo que espera al experto: ni la que todavia espera al '
          'administrador (SCRUM-321), ni la ya clasificada, ni la '
          'publicada, ni la rechazada, ni la que tiene la dificultad '
          'pendiente (criterio 3 de SCRUM-363)', () {
        for (final estado in [
          EstadoRuta.enRevision,
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
          EstadoRuta.revisionExperto,
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

  group('revision en dos etapas (SCRUM-321)', () {
    test('una ruta aprobada por el administrador sigue siendo legible', () {
      // Sin este estado, `desdeSupabase` lanzaria FormatException y se
      // romperian el detalle y "mis rutas" en cuanto el admin aprobara.
      final ruta = Ruta.desdeSupabase(fila(estado: 'revision_experto'));

      expect(ruta.estado, EstadoRuta.revisionExperto);
      expect(ruta.publicada, isFalse);
      expect(ruta.fechaPublicacion, isNull);
    });

    test('una ruta rechazada trae su motivo', () {
      final ruta = Ruta.desdeSupabase(
        fila(estado: 'rechazada', motivo: 'El trazado cruza una autopista'),
      );

      expect(ruta.estado, EstadoRuta.rechazada);
      expect(ruta.motivoRechazo, 'El trazado cruza una autopista');
    });
  });
}
