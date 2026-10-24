import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:traza/models/zona.dart';
import 'package:traza/services/zonas_service.dart';

/// Pruebas del buscador de zonas con Nominatim (SCRUM-255).
///
/// No sale a la red: un cliente HTTP falso contesta como Nominatim, con
/// respuestas copiadas de las de verdad, y anota lo que se le pidió. Así se
/// comprueba que se cumple su política de uso y que la caja se lee bien.
void main() {
  /// Envigado tal como lo devolvió Nominatim el 2026-10-23.
  Map<String, Object?> envigadoComoNominatim() => {
    'name': 'Envigado',
    'display_name':
        'Envigado, Valle de Aburrá, Antioquia, RAP del Agua y la '
        'Montaña, Colombia',
    'category': 'boundary',
    'type': 'administrative',
    'place_rank': 12,
    'boundingbox': ['6.1003036', '6.1983821', '-75.6049283', '-75.4741457'],
    'address': {
      'town': 'Envigado',
      'state_district': 'Valle de Aburrá',
      'state': 'Antioquia',
      'country': 'Colombia',
    },
  };

  group('qué le pregunta', () {
    test('lo escrito, solo en Colombia, en español y con la dirección del '
        'lugar', () async {
      final nominatim = _NominatimFalso();

      await nominatim.buscador().buscar('  Envigado  ');

      final url = nominatim.peticiones.single.url;
      expect(url.host, 'nominatim.openstreetmap.org');
      expect(url.path, '/search');
      expect(url.queryParameters, {
        'q': 'Envigado',
        'format': 'jsonv2',
        'limit': '5',
        'countrycodes': 'co',
        'accept-language': 'es',
        'addressdetails': '1',
      });
    });

    test('fuera del navegador se presenta con su User-Agent, como pide la '
        'política de Nominatim', () async {
      final nominatim = _NominatimFalso();

      await nominatim.buscador().buscar('Envigado');

      expect(
        nominatim.peticiones.single.headers['User-Agent'],
        NominatimBuscadorDeZonas.agente,
      );
    });

    test('en el navegador no lo toca: ahí la identifica el Referer', () async {
      final nominatim = _NominatimFalso();

      await nominatim.buscador(enNavegador: true).buscar('Envigado');

      expect(
        nominatim.peticiones.single.headers.containsKey('User-Agent'),
        isFalse,
      );
    });
  });

  group('lo que entiende de la respuesta', () {
    test('la caja y el nombre del lugar, con su departamento', () async {
      final nominatim = _NominatimFalso(lugares: [envigadoComoNominatim()]);

      final zona = await nominatim.buscador().buscar('Envigado');

      expect(
        zona,
        const Zona(
          nombre: 'Envigado',
          region: 'Antioquia',
          sur: 6.1003036,
          oeste: -75.6049283,
          norte: 6.1983821,
          este: -75.4741457,
        ),
      );
      expect(zona!.nombreCompleto, 'Envigado, Antioquia');
    });

    test('si el departamento es el mismo lugar, no lo repite', () async {
      final nominatim = _NominatimFalso(
        lugares: [
          {
            ...envigadoComoNominatim(),
            'name': 'Antioquia',
            'address': {'state': 'Antioquia'},
          },
        ],
      );

      final zona = await nominatim.buscador().buscar('Antioquia');

      expect(zona!.nombreCompleto, 'Antioquia');
    });

    test('sin nombre, toma el primero de la dirección completa', () async {
      final nominatim = _NominatimFalso(
        lugares: [
          {...envigadoComoNominatim(), 'name': ''},
        ],
      );

      final zona = await nominatim.buscador().buscar('Envigado');

      expect(zona!.nombre, 'Envigado');
    });

    test('a un lugar puntual le da una caja de al menos un kilómetro por '
        'lado', () async {
      // La cima de un cerro llega como un punto: en una caja de metros no
      // arranca ninguna ruta.
      final nominatim = _NominatimFalso(
        lugares: [
          {
            ...envigadoComoNominatim(),
            'name': 'Cerro El Volador',
            'category': 'natural',
            'type': 'peak',
            'boundingbox': ['6.2565', '6.2567', '-75.5901', '-75.5899'],
          },
        ],
      );

      final zona = await nominatim.buscador().buscar('El Volador');

      expect(zona!.norte - zona.sur, closeTo(0.02, 1e-9));
      expect(zona.este - zona.oeste, closeTo(0.02, 1e-9));
      // Sigue centrada en la cima.
      expect((zona.sur + zona.norte) / 2, closeTo(6.2566, 1e-9));
      expect((zona.oeste + zona.este) / 2, closeTo(-75.59, 1e-9));
    });

    test('un municipio conserva su límite tal cual', () async {
      final nominatim = _NominatimFalso(lugares: [envigadoComoNominatim()]);

      final zona = await nominatim.buscador().buscar('Envigado');

      expect(zona!.sur, 6.1003036);
      expect(zona.este, -75.4741457);
    });

    test('lo que no es un lugar no es una zona', () async {
      final nominatim = _NominatimFalso();

      expect(await nominatim.buscador().buscar('Subida al Nutibara'), isNull);
    });
  });

  group('cerca del usuario primero', () {
    test('con su ubicación busca solo a su alrededor, redondeada a la '
        'décima de grado', () async {
      final nominatim = _NominatimFalso(lugares: [envigadoComoNominatim()]);

      await nominatim.buscador().buscar(
        'Envigado',
        latitud: 6.2442,
        longitud: -75.5812,
      );

      final parametros = nominatim.peticiones.single.url.queryParameters;
      // Alrededor de (6.2, -75.6), ±0.2°: ni su posición exacta sale.
      expect(parametros['viewbox'], '-75.80,6.40,-75.40,6.00');
      expect(parametros['bounded'], '1');
    });

    test('si cerca no hay nada, busca en todo el país: Guatapé se encuentra '
        'desde Medellín', () async {
      final nominatim = _NominatimFalso(
        respuestas: [
          [],
          [
            {...envigadoComoNominatim(), 'name': 'Guatapé'},
          ],
        ],
      );

      final zona = await nominatim.buscador().buscar(
        'Guatapé',
        latitud: 6.2442,
        longitud: -75.5812,
      );

      expect(zona!.nombre, 'Guatapé');
      expect(nominatim.peticiones, hasLength(2));
      expect(
        nominatim.peticiones.last.url.queryParameters.containsKey('viewbox'),
        isFalse,
      );
    });
  });

  group('solo cuenta lo que de verdad es el lugar (SCRUM-256)', () {
    // Respuestas como las que dio Nominatim el 2026-10-23 para nombres de
    // persona: confirmar el nombre de alguien no puede sumar las rutas de un
    // lugar que nadie buscó.
    Map<String, Object?> lugar(
      String nombre, {
      required String categoria,
      required String tipo,
      required int rango,
    }) => {
      ...envigadoComoNominatim(),
      'name': nombre,
      'category': categoria,
      'type': tipo,
      'place_rank': rango,
    };

    test('una tienda o una casa que se llama como lo escrito no es una '
        'zona: "Luis"', () async {
      final nominatim = _NominatimFalso(
        lugares: [
          lugar('Luis', categoria: 'shop', tipo: 'supermarket', rango: 30),
          lugar('Luis', categoria: 'building', tipo: 'yes', rango: 30),
        ],
      );

      expect(await nominatim.buscador().buscar('Luis'), isNull);
    });

    test('un lugar que solo contiene lo escrito tampoco: "Ana" no es Santa '
        'Ana', () async {
      final nominatim = _NominatimFalso(
        lugares: [
          lugar(
            'Santa Ana',
            categoria: 'boundary',
            tipo: 'administrative',
            rango: 16,
          ),
        ],
      );

      expect(await nominatim.buscador().buscar('Ana'), isNull);
    });

    test('en todo el país, una localidad que se llama así no cuenta: '
        '"Carlos" en el Guainía', () async {
      final nominatim = _NominatimFalso(
        lugares: [
          lugar('Carlos', categoria: 'place', tipo: 'locality', rango: 25),
        ],
      );

      expect(await nominatim.buscador().buscar('Carlos'), isNull);
    });

    test('cerca del usuario, un barrio sí cuenta', () async {
      final nominatim = _NominatimFalso(
        lugares: [
          lugar(
            'Laureles',
            categoria: 'place',
            tipo: 'neighbourhood',
            rango: 22,
          ),
        ],
      );

      final zona = await nominatim.buscador().buscar(
        'Laureles',
        latitud: 6.2442,
        longitud: -75.5812,
      );

      expect(zona!.nombre, 'Laureles');
    });

    test('de los candidatos toma el primero que es la zona: Belén es la '
        'comuna, no la tienda', () async {
      final nominatim = _NominatimFalso(
        lugares: [
          lugar('Belén', categoria: 'shop', tipo: 'clothes', rango: 30),
          lugar(
            'Comuna 16 - Belén',
            categoria: 'boundary',
            tipo: 'administrative',
            rango: 16,
          ),
        ],
      );

      final zona = await nominatim.buscador().buscar(
        'Belén',
        latitud: 6.2442,
        longitud: -75.5812,
      );

      expect(zona!.nombre, 'Comuna 16 - Belén');
    });

    test('lo reconoce aunque lo acompañe "Comuna", "Parque" o "El"', () async {
      final nominatim = _NominatimFalso(
        respuestas: [
          [
            lugar(
              'Comuna 14 - El Poblado',
              categoria: 'boundary',
              tipo: 'administrative',
              rango: 16,
            ),
          ],
          [
            lugar(
              'Parque Arví',
              categoria: 'leisure',
              tipo: 'nature_reserve',
              rango: 12,
            ),
          ],
          [
            lugar(
              'Comuna 14 - El Poblado',
              categoria: 'boundary',
              tipo: 'administrative',
              rango: 16,
            ),
          ],
        ],
      );
      final buscador = nominatim.buscador();

      expect((await buscador.buscar('Poblado'))!.nombre, contains('Poblado'));
      expect((await buscador.buscar('Arví'))!.nombre, 'Parque Arví');
      expect((await buscador.buscar('Comuna 14'))!.nombre, contains('Comuna'));
    });
  });

  group('la política de uso', () {
    test('lo que ya encontró no lo vuelve a preguntar', () async {
      final nominatim = _NominatimFalso(lugares: [envigadoComoNominatim()]);
      final buscador = nominatim.buscador();

      await buscador.buscar('Envigado');
      await buscador.buscar('  ENVIGADO ');

      expect(nominatim.peticiones, hasLength(1));
    });

    test('dos búsquedas iguales a la vez salen como una sola', () async {
      final nominatim = _NominatimFalso(lugares: [envigadoComoNominatim()]);
      final buscador = nominatim.buscador();

      await Future.wait([
        buscador.buscar('Envigado'),
        buscador.buscar('envigado'),
      ]);

      expect(nominatim.peticiones, hasLength(1));
    });

    test('deja pasar el intervalo mínimo entre una consulta y otra', () async {
      final nominatim = _NominatimFalso(lugares: [envigadoComoNominatim()]);
      final buscador = nominatim.buscador(
        intervaloMinimo: const Duration(milliseconds: 150),
      );

      await Future.wait([
        buscador.buscar('Envigado'),
        buscador.buscar('Sabaneta'),
      ]);

      final [primera, segunda] = nominatim.momentos;
      expect(
        segunda.difference(primera),
        greaterThanOrEqualTo(const Duration(milliseconds: 150)),
      );
    });
  });

  group('cuando no se puede', () {
    test(
      'sin conexión no revienta: avisa que la zona no está disponible',
      () async {
        final nominatim = _NominatimFalso(sinConexion: true);

        await expectLater(
          nominatim.buscador().buscar('Envigado'),
          throwsA(isA<ZonaNoDisponibleException>()),
        );
      },
    );

    test('si el servicio responde con un error, tampoco', () async {
      final nominatim = _NominatimFalso(codigo: 429);

      await expectLater(
        nominatim.buscador().buscar('Envigado'),
        throwsA(isA<ZonaNoDisponibleException>()),
      );
    });

    test('si no responde a tiempo, deja de esperar', () async {
      final nominatim = _NominatimFalso(
        demora: const Duration(milliseconds: 300),
      );

      await expectLater(
        nominatim
            .buscador(tiempoMaximo: const Duration(milliseconds: 50))
            .buscar('Envigado'),
        throwsA(isA<ZonaNoDisponibleException>()),
      );
    });

    test('si la respuesta no se entiende, tampoco revienta', () async {
      final nominatim = _NominatimFalso(cuerpo: '<html>mantenimiento</html>');

      await expectLater(
        nominatim.buscador().buscar('Envigado'),
        throwsA(isA<ZonaNoDisponibleException>()),
      );
    });

    test('un fallo no se guarda: al reintentar vuelve a preguntar', () async {
      final nominatim = _NominatimFalso(codigo: 503);
      final buscador = nominatim.buscador();

      await expectLater(
        buscador.buscar('Envigado'),
        throwsA(isA<ZonaNoDisponibleException>()),
      );
      nominatim
        ..codigo = 200
        ..respuestas = [
          [envigadoComoNominatim()],
        ];

      expect((await buscador.buscar('Envigado'))!.nombre, 'Envigado');
      expect(nominatim.peticiones, hasLength(2));
    });
  });
}

/// Un Nominatim de mentira: contesta lo que la prueba le indique y anota lo
/// que se le pidió y cuándo.
class _NominatimFalso {
  _NominatimFalso({
    List<Map<String, Object?>> lugares = const [],
    List<List<Map<String, Object?>>>? respuestas,
    this.codigo = 200,
    this.sinConexion = false,
    this.demora,
    this.cuerpo,
  }) : respuestas = respuestas ?? [lugares];

  /// Lo que devuelve cada consulta, en orden; la última se repite.
  List<List<Map<String, Object?>>> respuestas;

  int codigo;
  final bool sinConexion;
  final Duration? demora;

  /// Si no es null, se devuelve tal cual en vez de JSON.
  final String? cuerpo;

  final peticiones = <http.Request>[];
  final momentos = <DateTime>[];

  NominatimBuscadorDeZonas buscador({
    bool enNavegador = false,
    Duration intervaloMinimo = Duration.zero,
    Duration tiempoMaximo = const Duration(seconds: 8),
  }) => NominatimBuscadorDeZonas(
    cliente: MockClient(_responder),
    enNavegador: enNavegador,
    intervaloMinimo: intervaloMinimo,
    tiempoMaximo: tiempoMaximo,
  );

  Future<http.Response> _responder(http.Request peticion) async {
    peticiones.add(peticion);
    momentos.add(DateTime.now());

    if (sinConexion) throw http.ClientException('Sin conexión', peticion.url);
    final demora = this.demora;
    if (demora != null) await Future<void>.delayed(demora);

    final indice = (peticiones.length - 1).clamp(0, respuestas.length - 1);
    return http.Response.bytes(
      utf8.encode(cuerpo ?? jsonEncode(respuestas[indice])),
      codigo,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: peticion,
    );
  }
}
