import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/estado_cronometro.dart';
import '../models/punto_gps.dart';
import '../models/punto_pendiente.dart';
import '../models/recorrido.dart';
import 'almacen_recorrido.dart';
import 'calculadora_distancia.dart';
import 'criterio_movimiento.dart';
import 'cronometro_provider.dart';
import 'entrenamiento_actual_provider.dart';
import 'puntos_gps_service.dart';
import 'ubicacion_provider.dart';

// El `id` del entrenamiento dueño de los puntos lo fija el flujo de inicio
// (SCRUM-99). Se re-exporta para que quien registre puntos no tenga que
// saber de dónde sale.
export 'entrenamiento_actual_provider.dart' show entrenamientoActualProvider;

/// Persistencia real. Las pruebas la sobrescriben.
final repositorioPuntosGpsProvider = Provider<RepositorioPuntosGps>(
  (ref) => RepositorioPuntosGpsSupabase(Supabase.instance.client),
);

/// Recorrido de la actividad en curso (SCRUM-110): cada lectura aceptada
/// de [posicionEnVivoProvider] se guarda en disco y, cada
/// [RecorridoNotifier.puntosPorLote], se intenta enviar lo pendiente a
/// `puntos_gps` (SCRUM-292). Al finalizar,
/// [RecorridoNotifier.sincronizar] manda lo que quede.
///
/// Antes los puntos vivían solo en memoria y se subían todos al final: sin
/// red en ese momento se perdía el recorrido entero, y salir de la pantalla
/// o que el sistema matara la app lo remataba.
///
/// Solo registra y expone. Dibujar el trazo y calcular la distancia son
/// de otras HU: leen `puntos` de aquí. Vive mientras la pantalla de
/// entrenamiento lo observe.
final recorridoProvider =
    NotifierProvider.autoDispose<RecorridoNotifier, Recorrido>(
      RecorridoNotifier.new,
    );

class RecorridoNotifier extends AutoDisposeNotifier<Recorrido> {
  /// Cada cuántos puntos guardados se intenta enviar lo pendiente.
  ///
  /// Con una lectura cada 5 m, son unos 100 m: lo bastante seguido para que
  /// una caída de red deje fuera poco recorrido, y lo bastante espaciado
  /// para no hacer una petición por paso.
  static const puntosPorLote = 20;

  bool _activo = true;

  /// La siguiente lectura registrada empieza un tramo nuevo: se acaba de
  /// reanudar tras una pausa.
  bool _tramoNuevo = false;

  /// En qué tramo van los puntos que se registren ahora: 0 hasta la primera
  /// pausa, 1 hasta la siguiente... (columna `tramo`, 0007).
  int _tramo = 0;

  /// El `orden_secuencia` del siguiente punto. Se decide al capturarlo, no
  /// al enviarlo: los lotes salen poco a poco y cada punto tiene que
  /// conservar su sitio.
  int _siguienteOrden = 0;

  /// Puntos guardados desde el último envío que salió bien.
  int _sinEnviar = 0;

  /// Hay un envío en curso: no se lanza otro encima.
  bool _enviando = false;

  @override
  Recorrido build() {
    _activo = true;
    _tramo = 0;
    _siguienteOrden = 0;
    _sinEnviar = 0;
    _enviando = false;
    ref.onDispose(() => _activo = false);

    ref.listen(posicionEnVivoProvider, (_, siguiente) {
      final punto = siguiente.valueOrNull;
      if (punto != null) _registrar(punto);
    });

    ref.listen(cronometroProvider.select((estado) => estado.marcha), (
      anterior,
      actual,
    ) {
      if (anterior == MarchaCronometro.pausado &&
          actual == MarchaCronometro.enCurso) {
        _tramoNuevo = true;
      }
    });

    return const Recorrido();
  }

  /// Registra la lectura: a la vista y al disco.
  void _registrar(PuntoGps punto) {
    // En pausa (o ya finalizado) el usuario no está haciendo la ruta:
    // la lectura no cuenta, igual que en el prototipo.
    if (!ref.read(cronometroProvider).estaEnCurso) return;
    if (_tramoNuevo && state.puntos.isNotEmpty) {
      // Lo que el usuario se movió en pausa no es parte de la ruta: la
      // primera lectura tras reanudar no se compara con el último punto de
      // antes, sino que abre un tramo nuevo (BUG-005).
      _tramoNuevo = false;
      _tramo++;
      state = state.copyWith(
        puntos: [...state.puntos, punto],
        cortes: [...state.cortes, state.puntos.length],
      );
      _guardar(punto);
      return;
    }
    if (!_esAvance(punto)) return;
    state = state.copyWith(puntos: [...state.puntos, punto]);
    _guardar(punto);
  }

  /// Escribe el punto en disco y, cada [puntosPorLote], intenta enviar lo
  /// que haya pendiente.
  ///
  /// No se espera a que termine: el trazo y la distancia no pueden quedarse
  /// esperando al disco ni a la red. Si el guardado falla, se pierde ese
  /// punto y no el recorrido, y el siguiente lo vuelve a intentar.
  void _guardar(PuntoGps punto) {
    final entrenamientoId = ref.read(entrenamientoActualProvider);
    // Sin entrenamiento creado no hay a qué asociarlo. Pasa en las pruebas
    // de pantalla y antes de que exista la fila.
    if (entrenamientoId == null) return;

    final pendiente = PuntoPendiente.de(
      punto,
      orden: _siguienteOrden++,
      tramo: _tramo,
    );

    unawaited(() async {
      try {
        await ref
            .read(almacenRecorridoProvider)
            .anadir(entrenamientoId, pendiente);
      } catch (error) {
        debugPrint('No se pudo guardar el punto en disco: $error');
        return;
      }
      _sinEnviar++;
      if (_sinEnviar < puntosPorLote) return;
      // La cuenta se reinicia antes de intentarlo, no después de que salga
      // bien: si no, con la red caída el primer fallo deja el contador por
      // encima del lote y cada punto siguiente vuelve a intentarlo. Se veía
      // en el emulador como una petición cada dos segundos. Lo pendiente
      // sigue en disco, así que esperar al siguiente lote no pierde nada.
      _sinEnviar = 0;
      await enviarPendientes();
    }());
  }

  /// `true` si [punto] alarga el trazo.
  ///
  /// El sistema entrega todas las lecturas (una por segundo), así que el
  /// filtro de ruido es este (SCRUM-116): con el usuario quieto el GPS
  /// "baila" hasta decenas de metros y el trazo acumularía zigzags
  /// fantasma. Hace falta separarse `distanciaMinimaRegistroMetros`
  /// del último punto y, además, que haya movimiento: según la velocidad
  /// Doppler si es fiable, o si no, un desplazamiento mayor que el error
  /// de las lecturas.
  bool _esAvance(PuntoGps punto) {
    final ultimo = state.ultimo;
    if (ultimo == null) return true;

    final avance = CalculadoraDistancia.haversineMetros(
      ultimo.latitud,
      ultimo.longitud,
      punto.latitud,
      punto.longitud,
    );
    final minimo = ref
        .read(configuracionRastreoProvider)
        .distanciaMinimaRegistroMetros;
    if (avance < minimo) return false;

    const criterio = CriterioMovimiento();
    final velocidad = criterio.velocidadFiable(punto);
    if (velocidad != null) return criterio.esMovimiento(velocidad);

    // Sin velocidad fiable basta con salir del radio de error. Es más
    // permisivo que el umbral de la distancia (2.5 × el error): un zigzag
    // en el trazo apenas se nota, pero un marcador que no avanza sí. Los
    // kilómetros no salen de aquí, así que no se inflan.
    final ruido = math.max(
      ultimo.precisionMetros ?? 0,
      punto.precisionMetros ?? 0,
    );
    return avance >= ruido;
  }

  /// Manda a `puntos_gps` lo que quede pendiente.
  ///
  /// Se llama al finalizar la actividad. Devuelve `true` si ya no queda
  /// nada por enviar. Si falla, los puntos siguen en disco y se puede
  /// volver a llamar, ahora o en el próximo arranque de la app.
  Future<bool> sincronizar() => enviarPendientes();

  /// Envía el lote de lo que todavía no aceptó la base.
  ///
  /// Un envío a la vez: durante la actividad esto se dispara cada
  /// [puntosPorLote] puntos, y al finalizar otra vez; si uno sigue en
  /// curso, el siguiente se descarta en vez de mandar lo mismo dos veces.
  Future<bool> enviarPendientes() async {
    final entrenamientoId = ref.read(entrenamientoActualProvider);
    if (entrenamientoId == null) {
      _actualizar(EstadoSincronizacion.completada);
      return true;
    }
    if (_enviando) return false;
    _enviando = true;

    final almacen = ref.read(almacenRecorridoProvider);
    try {
      final pendientes = await almacen.pendientes(entrenamientoId);
      if (pendientes.isEmpty) {
        _actualizar(EstadoSincronizacion.completada);
        return true;
      }

      _actualizar(EstadoSincronizacion.enCurso);
      await ref
          .read(repositorioPuntosGpsProvider)
          .guardarLote(entrenamientoId: entrenamientoId, puntos: pendientes);
      // Solo después de que la base lo acepte: si el proceso muere entre
      // una cosa y la otra, el lote se reenvía y el índice único lo
      // descarta (0053).
      await almacen.marcarEnviados(entrenamientoId, pendientes.last.orden);

      _actualizar(EstadoSincronizacion.completada);
      return true;
    } catch (error) {
      debugPrint('No se pudo enviar el recorrido: $error');
      _actualizar(EstadoSincronizacion.fallida);
      return false;
    } finally {
      _enviando = false;
    }
  }

  void _actualizar(EstadoSincronizacion sincronizacion) {
    if (_activo) state = state.copyWith(sincronizacion: sincronizacion);
  }
}
