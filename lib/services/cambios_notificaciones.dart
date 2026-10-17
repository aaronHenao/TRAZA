import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// De dónde salen los avisos de que llegó una notificación. Las pruebas lo
/// sustituyen con `overrideWithValue`.
final fuenteCambiosNotificacionesProvider =
    Provider<FuenteCambiosNotificaciones>(
      (ref) => SupabaseCambiosNotificaciones(),
    );

/// Qué pasó con las notificaciones de alguien.
enum TipoCambioNotificaciones {
  /// Le llegó una.
  nueva,

  /// La conexión se cayó y volvió: pudo llegar algo que no se vio.
  reconectado,
}

/// Aviso de que las notificaciones de alguien cambiaron.
///
/// No trae la fila: la app vuelve a consultar, así lo que se muestra sale de
/// la misma consulta de siempre y pasa por las policies de select.
@immutable
class CambioNotificaciones {
  const CambioNotificaciones(this.tipo);

  const CambioNotificaciones.reconectado()
    : this(TipoCambioNotificaciones.reconectado);

  final TipoCambioNotificaciones tipo;

  @override
  String toString() => 'CambioNotificaciones(${tipo.name})';
}

/// Las notificaciones que le llegan a alguien mientras alguien las escucha.
///
/// El `Stream` abre su suscripción al primer `listen` y la cierra al
/// cancelarla: la conexión solo existe mientras hay una pantalla que la mire.
abstract interface class FuenteCambiosNotificaciones {
  Stream<CambioNotificaciones> de(String usuarioId);
}

/// Supabase Realtime (WebSocket, Postgres Changes).
///
/// Realtime reparte cada evento solo a quien la policy de select deja ver la
/// fila, así que los avisos de uno no salen de su dueño. El filtro por
/// `usuario_id` va además de eso: la barrera es la policy, pero no cuesta
/// nada no pedir lo ajeno.
class SupabaseCambiosNotificaciones implements FuenteCambiosNotificaciones {
  /// [cliente] existe para las pruebas. En la app se usa el cliente global.
  SupabaseCambiosNotificaciones({SupabaseClient? cliente})
    : _clienteInyectado = cliente;

  final SupabaseClient? _clienteInyectado;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  /// Cada suscripción en su propio canal: dos pantallas abiertas a la vez no
  /// se pisan el tema.
  static var _siguienteCanal = 0;

  static const _tabla = 'notificaciones';

  @override
  Stream<CambioNotificaciones> de(String usuarioId) {
    RealtimeChannel? canal;
    late final StreamController<CambioNotificaciones> salida;

    void emitir(CambioNotificaciones cambio) {
      if (!salida.isClosed) salida.add(cambio);
    }

    salida = StreamController<CambioNotificaciones>(
      onListen: () {
        final abierto = _cliente.channel(
          'notificaciones:$usuarioId:${_siguienteCanal++}',
        );
        canal = abierto;

        // Solo las nuevas: marcar una como leída lo hace esta misma app, y
        // recargar por eso sería perseguirse la cola.
        abierto.onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _tabla,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'usuario_id',
            value: usuarioId,
          ),
          callback: (_) =>
              emitir(const CambioNotificaciones(TipoCambioNotificaciones.nueva)),
        );

        var suscritoAntes = false;
        var caido = false;
        abierto.subscribe((estado, error) {
          switch (estado) {
            case RealtimeSubscribeStatus.subscribed:
              // Volvió después de caerse: pudo perderse algo.
              if (suscritoAntes && caido) {
                emitir(const CambioNotificaciones.reconectado());
              }
              suscritoAntes = true;
              caido = false;
            case RealtimeSubscribeStatus.channelError ||
                RealtimeSubscribeStatus.timedOut ||
                RealtimeSubscribeStatus.closed:
              caido = true;
              if (error != null) {
                debugPrint('Realtime de las notificaciones: $error');
              }
          }
        });
      },
      onCancel: () async {
        final abierto = canal;
        canal = null;
        // Al quitar el último canal, el cliente cierra el WebSocket.
        if (abierto != null) await _cliente.removeChannel(abierto);
      },
    );

    return salida.stream;
  }
}
