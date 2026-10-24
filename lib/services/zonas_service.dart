import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/zona.dart';

/// No se pudo preguntar por la zona: sin conexión, sin respuesta a tiempo o
/// con un error del servicio.
class ZonaNoDisponibleException implements Exception {
  const ZonaNoDisponibleException(this.motivo);

  final String motivo;

  @override
  String toString() => 'ZonaNoDisponibleException: $motivo';
}

/// Convierte el nombre de un lugar en una [Zona] (SCRUM-255).
abstract class BuscadorDeZonas {
  /// La zona que nombra [texto], o null si no es ningún lugar conocido.
  ///
  /// Con [latitud] y [longitud], que es donde está el usuario, prefiere los
  /// lugares cercanos: para quien está en Medellín, "Belén" es la comuna y
  /// no el municipio de Boyacá.
  ///
  /// Lanza [ZonaNoDisponibleException] si no se pudo preguntar.
  Future<Zona?> buscar(String texto, {double? latitud, double? longitud});
}

/// [BuscadorDeZonas] con Nominatim, el buscador de OpenStreetMap.
///
/// No pide clave y devuelve el límite real de cada municipio o comuna, no
/// una caja genérica alrededor de su centro. Su política de uso
/// (operations.osmfoundation.org/policies/nominatim) pide cinco cosas, y
/// las cinco se cumplen aquí:
///
/// - Que la app se identifique: fuera del navegador va [agente] como
///   User-Agent. En el navegador ese encabezado no se puede cambiar, y la
///   identifica el Referer, que pone el propio navegador.
/// - Como mucho una consulta por segundo: van de a una, con
///   [intervaloMinimo] entre una y otra.
/// - Nada de autocompletar: la pantalla solo pregunta cuando el usuario
///   confirma la búsqueda, nunca con cada letra.
/// - Guardar lo encontrado: la misma zona no se pregunta dos veces.
/// - Atribuir: la pantalla muestra "© OpenStreetMap" junto a la zona.
///
/// Lo que se manda es lo que el usuario escribió y, si se sabe, una caja de
/// unos 20 km alrededor de él, redondeada a la décima de grado: suficiente
/// para preferir lo cercano, sin dar su posición exacta.
class NominatimBuscadorDeZonas implements BuscadorDeZonas {
  NominatimBuscadorDeZonas({
    http.Client? cliente,
    this.enNavegador = kIsWeb,
    this.intervaloMinimo = const Duration(seconds: 1),
    this.tiempoMaximo = const Duration(seconds: 8),
  }) : _cliente = cliente ?? http.Client();

  final http.Client _cliente;

  /// Si la app corre en un navegador, donde el User-Agent no se toca.
  final bool enNavegador;

  /// Lo que se espera entre una consulta y la siguiente.
  final Duration intervaloMinimo;

  /// Lo que se espera la respuesta antes de darla por perdida.
  final Duration tiempoMaximo;

  /// Cómo se presenta la app ante Nominatim.
  static const agente = 'TRAZA/1.0 (+https://github.com/aaronHenao/TRAZA)';

  /// Cuánto alrededor del usuario es "cerca": ±0,2°, unos 22 km. Desde
  /// Medellín cubre el Valle de Aburrá y deja fuera a la vereda Laureles de
  /// Santa Fe de Antioquia, que de otro modo le gana al barrio Laureles.
  static const radioCercaGrados = 0.2;

  /// La mitad del lado más corto que se acepta en una zona: 0,01°, poco más
  /// de un kilómetro. Un lugar puntual, como un estadio, trae una caja de
  /// metros en la que no arranca ninguna ruta.
  static const mediaCajaMinima = 0.01;

  /// TRAZA es para Colombia: buscar en otros países solo traería homónimos.
  static const pais = 'co';

  static const _servidor = 'nominatim.openstreetmap.org';

  /// Lo encontrado, por texto y por zona del usuario. Se guarda el `Future`
  /// para que dos búsquedas iguales a la vez salgan como una sola.
  final _encontradas = <String, Future<Zona?>>{};

  /// Cuándo puede salir la próxima consulta.
  Future<void> _turno = Future<void>.value();

  @override
  Future<Zona?> buscar(String texto, {double? latitud, double? longitud}) {
    final buscado = texto.trim().replaceAll(RegExp(r'\s+'), ' ');
    final cerca = latitud != null && longitud != null
        ? (latitud: _redondear(latitud), longitud: _redondear(longitud))
        : null;
    final clave =
        '${buscado.toLowerCase()}|${cerca?.latitud},${cerca?.longitud}';

    return _encontradas[clave] ??= _guardando(
      clave,
      _preguntar(buscado, cerca),
    );
  }

  /// Si falla, no se guarda: así se puede reintentar.
  Future<Zona?> _guardando(String clave, Future<Zona?> busqueda) async {
    try {
      return await busqueda;
    } catch (_) {
      _encontradas.remove(clave);
      rethrow;
    }
  }

  /// Primero cerca del usuario y solo ahí. Si no hay nada, en todo el país:
  /// así "Guatapé" se encuentra desde Medellín aunque quede lejos.
  Future<Zona?> _preguntar(
    String texto,
    ({double latitud, double longitud})? cerca,
  ) async {
    if (cerca != null) {
      final cercana = await _porTurno(() => _consultar(texto, cerca: cerca));
      if (cercana != null) return cercana;
    }
    return _porTurno(() => _consultar(texto));
  }

  /// De a una consulta, y la siguiente cuando pase [intervaloMinimo].
  Future<T> _porTurno<T>(Future<T> Function() consulta) {
    final resultado = _turno.then((_) => consulta());
    _turno = resultado
        .then<void>((_) {}, onError: (_) {})
        .then((_) => Future<void>.delayed(intervaloMinimo));
    return resultado;
  }

  Future<Zona?> _consultar(
    String texto, {
    ({double latitud, double longitud})? cerca,
  }) async {
    final url = Uri.https(_servidor, '/search', {
      'q': texto,
      'format': 'jsonv2',
      'limit': '1',
      'countrycodes': pais,
      'accept-language': 'es',
      'addressdetails': '1',
      if (cerca != null) ...{
        'viewbox': [
          cerca.longitud - radioCercaGrados,
          cerca.latitud + radioCercaGrados,
          cerca.longitud + radioCercaGrados,
          cerca.latitud - radioCercaGrados,
        ].map((borde) => borde.toStringAsFixed(2)).join(','),
        'bounded': '1',
      },
    });

    final http.Response respuesta;
    try {
      respuesta = await _cliente
          .get(url, headers: {if (!enNavegador) 'User-Agent': agente})
          .timeout(tiempoMaximo);
    } on TimeoutException {
      throw const ZonaNoDisponibleException('sin respuesta a tiempo');
    } on http.ClientException catch (error) {
      throw ZonaNoDisponibleException('sin conexión: ${error.message}');
    }

    if (respuesta.statusCode != 200) {
      throw ZonaNoDisponibleException('respondió ${respuesta.statusCode}');
    }

    try {
      final lugares = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (lugares is! List || lugares.isEmpty) return null;
      return _zonaDe(lugares.first);
    } on FormatException catch (error) {
      throw ZonaNoDisponibleException('respuesta ilegible: ${error.message}');
    }
  }

  /// Una [Zona] a partir de un lugar de Nominatim, o null si no trae caja.
  static Zona? _zonaDe(Object? lugar) {
    if (lugar is! Map) return null;
    final caja = lugar['boundingbox'];
    if (caja is! List || caja.length != 4) return null;

    // Nominatim da la caja como [sur, norte, oeste, este], en texto.
    final bordes = [for (final borde in caja) double.parse('$borde')];
    var sur = bordes[0], norte = bordes[1], oeste = bordes[2], este = bordes[3];

    if (norte - sur < 2 * mediaCajaMinima) {
      final centro = (sur + norte) / 2;
      sur = math.max(centro - mediaCajaMinima, -90);
      norte = math.min(centro + mediaCajaMinima, 90);
    }
    if (este - oeste < 2 * mediaCajaMinima) {
      final centro = (oeste + este) / 2;
      oeste = math.max(centro - mediaCajaMinima, -180);
      este = math.min(centro + mediaCajaMinima, 180);
    }

    final nombre = '${lugar['name'] ?? ''}'.trim();
    final completo = '${lugar['display_name'] ?? ''}'.split(',').first.trim();
    final visible = nombre.isNotEmpty ? nombre : completo;
    final direccion = lugar['address'];
    final estado = direccion is Map ? direccion['state'] : null;
    final region = estado is String ? estado.trim() : null;

    return Zona(
      nombre: visible,
      region: region == null || region == visible ? null : region,
      sur: sur,
      oeste: oeste,
      norte: norte,
      este: este,
    );
  }

  /// A la décima de grado, unos 11 km.
  static double _redondear(double grados) => (grados * 10).round() / 10;
}

/// Quién convierte nombres de lugares en zonas. Las pruebas lo sobrescriben
/// para no salir a la red.
final buscadorDeZonasProvider = Provider<BuscadorDeZonas>((ref) {
  final cliente = http.Client();
  ref.onDispose(cliente.close);
  return NominatimBuscadorDeZonas(cliente: cliente);
});
