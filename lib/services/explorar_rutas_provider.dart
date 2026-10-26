import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/punto_gps.dart';
import '../models/ruta.dart';
import '../models/ruta_cercana.dart';
import 'rutas_service.dart';
import 'ubicacion_provider.dart';

/// Hasta dónde se buscan rutas cercanas (SCRUM-246).
///
/// 50 km cubren de sobra una ciudad con su área metropolitana. Lo que esté
/// más lejos no es "cerca" y lo encuentra la búsqueda por lugar (HU-30),
/// que existe justo para eso.
const radioRutasCercanasKm = 50.0;

/// Lo que muestra Explorar rutas y en qué orden (SCRUM-246).
///
/// Es un tipo cerrado porque la pantalla tiene que contar distinto los dos
/// casos: no es lo mismo una lista ordenada por cercanía que una que no se
/// pudo ordenar porque no se sabe dónde está el usuario.
sealed class RutasParaExplorar {
  const RutasParaExplorar();

  /// Las rutas, ya en el orden en que se muestran.
  List<Ruta> get rutas;
}

/// Ordenadas de la más cercana a la más lejana (criterio 1 de HU-29).
class RutasPorCercania extends RutasParaExplorar {
  const RutasPorCercania({required this.cercanas, required this.desde});

  /// Con la distancia de cada una al usuario, en el orden de la base.
  final List<RutaCercana> cercanas;

  /// Dónde estaba el usuario cuando se ordenaron.
  final PuntoGps desde;

  @override
  List<Ruta> get rutas => [for (final cercana in cercanas) cercana.ruta];
}

/// Las más recientes, porque no se sabe dónde está el usuario.
///
/// Mejor eso que dejar la sección vacía: se puede explorar igual, y
/// [motivo] dice por qué no van por cercanía para que la pantalla lo cuente.
class RutasRecientes extends RutasParaExplorar {
  const RutasRecientes({required this.rutas, required this.motivo});

  @override
  final List<Ruta> rutas;

  /// Sin permiso, con la ubicación apagada o sin respuesta del GPS.
  final UbicacionUsuario motivo;
}

/// Las rutas de Explorar rutas (SCRUM-246).
///
/// Junta las dos piezas anteriores de la HU: la ubicación del usuario
/// (SCRUM-245) y la consulta por cercanía de la base (0037). Si no se sabe
/// dónde está, no se queda en blanco: muestra las publicadas más recientes.
///
/// `autoDispose`: cada vez que se entra a la sección se vuelve a leer la
/// ubicación y a consultar, porque el usuario se movió o la comunidad
/// publicó algo desde la última vez.
final rutasParaExplorarProvider = FutureProvider.autoDispose<RutasParaExplorar>(
  (ref) async {
    final ubicacion = await ref.watch(ubicacionActualProvider.future);
    final repositorio = ref.watch(rutasRepositoryProvider);

    if (ubicacion case UbicacionConocida(:final punto)) {
      final cercanas = await repositorio.cercanas(
        latitud: punto.latitud,
        longitud: punto.longitud,
        radioKm: radioRutasCercanasKm,
      );
      return RutasPorCercania(cercanas: cercanas, desde: punto);
    }

    return RutasRecientes(
      rutas: await repositorio.publicadas(),
      motivo: ubicacion,
    );
  },
);
