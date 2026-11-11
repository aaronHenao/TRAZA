import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dificultad.dart';
import '../models/rango_distancia.dart';

/// Dónde se recuerdan los filtros de Explorar rutas entre una visita y otra
/// (preferencias de Explorar, Desarrollo Móvil).
///
/// Es una preferencia del teléfono, no un dato de la cuenta: no viaja a
/// Supabase y no dice nada de la persona.
abstract interface class PreferenciasExplorar {
  /// La dificultad guardada, o null si no hay o no se reconoce.
  Dificultad? dificultad();

  /// El rango de distancia guardado, o null si no hay o no se reconoce.
  RangoDistancia? distancia();

  /// Guarda la dificultad elegida. Null borra lo guardado.
  Future<void> guardarDificultad(Dificultad? dificultad);

  /// Guarda el rango elegido. Null borra lo guardado.
  Future<void> guardarDistancia(RangoDistancia? distancia);
}

/// En el teléfono, con SharedPreferences. `main` la crea con la instancia
/// ya cargada, así leer es inmediato y Explorar abre con sus filtros.
class PreferenciasExplorarCompartidas implements PreferenciasExplorar {
  PreferenciasExplorarCompartidas(this._preferencias);

  /// Las del teléfono, ya cargadas. Supabase usa la misma instancia para la
  /// sesión, así que al arrancar ya está en memoria y no tarda.
  static Future<PreferenciasExplorarCompartidas> cargar() async =>
      PreferenciasExplorarCompartidas(await SharedPreferences.getInstance());

  final SharedPreferences _preferencias;

  /// La dificultad va como en la base (`Dificultad.valorDb`) y el rango
  /// por su nombre: valores estables, que no cambian con el texto del chip.
  static const claveDificultad = 'explorar.dificultad';
  static const claveDistancia = 'explorar.distancia';

  // `get` y no `getString`: si en la clave hubiera otra cosa (un número de
  // una versión vieja), `getString` lanzaría. Lo que no se reconoce se lee
  // como "sin filtro".
  @override
  Dificultad? dificultad() {
    final valor = _preferencias.get(claveDificultad);
    return valor is String ? Dificultad.desdeDb(valor) : null;
  }

  @override
  RangoDistancia? distancia() {
    final valor = _preferencias.get(claveDistancia);
    if (valor is! String) return null;
    for (final rango in RangoDistancia.values) {
      if (rango.name == valor) return rango;
    }
    return null;
  }

  @override
  Future<void> guardarDificultad(Dificultad? dificultad) async {
    if (dificultad == null) {
      await _preferencias.remove(claveDificultad);
    } else {
      await _preferencias.setString(claveDificultad, dificultad.valorDb);
    }
  }

  @override
  Future<void> guardarDistancia(RangoDistancia? distancia) async {
    if (distancia == null) {
      await _preferencias.remove(claveDistancia);
    } else {
      await _preferencias.setString(claveDistancia, distancia.name);
    }
  }
}

/// Sin persistencia: lo que usa la app si nadie la sustituye, como en las
/// pruebas. Recuerda mientras viva, nada más.
class PreferenciasExplorarEnMemoria implements PreferenciasExplorar {
  Dificultad? _dificultad;
  RangoDistancia? _distancia;

  @override
  Dificultad? dificultad() => _dificultad;

  @override
  RangoDistancia? distancia() => _distancia;

  @override
  Future<void> guardarDificultad(Dificultad? dificultad) async =>
      _dificultad = dificultad;

  @override
  Future<void> guardarDistancia(RangoDistancia? distancia) async =>
      _distancia = distancia;
}

/// `main` la sustituye con [PreferenciasExplorarCompartidas].
final preferenciasExplorarProvider = Provider<PreferenciasExplorar>(
  (ref) => PreferenciasExplorarEnMemoria(),
);
