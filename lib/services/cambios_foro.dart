import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// De dónde salen los avisos de cambios del foro. Las pruebas lo sustituyen
/// con `overrideWithValue`.
final fuenteCambiosForoProvider = Provider<FuenteCambiosForo>(
  (ref) => SupabaseCambiosForo(),
);

/// Qué tabla cambió.
enum TablaForo { publicaciones, comentarios }

/// Qué pasó.
enum TipoCambioForo {
  /// Se insertó una fila.
  nuevo,

  /// Se editó una fila.
  editado,

  /// La conexión se cayó y volvió: pudo haber cambios que no llegaron.
  reconectado,
}

/// Aviso de que algo cambió en el foro (SCRUM-357).
///
/// No trae la fila: la app vuelve a consultar, así lo que se muestra sale de
/// la misma consulta de siempre y pasa por las policies de select.
@immutable
class CambioForo {
  const CambioForo({
    required this.tipo,
    this.tabla,
    this.id,
    this.publicacionId,
    this.autorId,
  });

  const CambioForo.reconectado() : this(tipo: TipoCambioForo.reconectado);

  final TipoCambioForo tipo;
  final TablaForo? tabla;
  final String? id;

  /// En un comentario, la publicación a la que pertenece.
  final String? publicacionId;

  /// Quién escribió la fila, para no anunciarle al autor lo que él mismo
  /// acaba de publicar.
  final String? autorId;

  bool get esPublicacionNueva =>
      tipo == TipoCambioForo.nuevo && tabla == TablaForo.publicaciones;

  @override
  String toString() => 'CambioForo(${tipo.name}, ${tabla?.name}, $id)';
}

/// Los cambios del foro mientras alguien los escucha (SCRUM-357).
///
/// Cada `Stream` abre su suscripción al primer `listen` y la cierra al
/// cancelarla: la conexión solo existe mientras hay una pantalla del foro
/// abierta.
abstract interface class FuenteCambiosForo {
  /// Publicaciones y comentarios de todo el foro.
  Stream<CambioForo> delForo();

  /// Una publicación y sus comentarios.
  Stream<CambioForo> deLaPublicacion(String publicacionId);
}

/// Supabase Realtime (WebSocket, Postgres Changes). Realtime reparte cada
/// evento solo a quien la policy de select deja ver la fila.
class SupabaseCambiosForo implements FuenteCambiosForo {
  /// [cliente] existe para las pruebas. En la app se usa el cliente global.
  SupabaseCambiosForo({SupabaseClient? cliente}) : _clienteInyectado = cliente;

  final SupabaseClient? _clienteInyectado;

  SupabaseClient get _cliente => _clienteInyectado ?? Supabase.instance.client;

  /// Cada suscripción en su propio canal: dos pantallas abiertas a la vez no
  /// se pisan el tema.
  static var _siguienteCanal = 0;

  static const _tablaPublicaciones = 'publicaciones_foro';
  static const _tablaComentarios = 'comentarios_foro';

  @override
  Stream<CambioForo> delForo() => _escuchar('foro', (canal, emitir) {
    canal
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: _tablaPublicaciones,
        callback: (p) => emitir(_cambio(TablaForo.publicaciones, p)),
      )
      // Solo los nuevos: en el listado se ve cuántos comentarios hay, no lo
      // que dicen.
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: _tablaComentarios,
        callback: (p) => emitir(_cambio(TablaForo.comentarios, p)),
      );
  });

  @override
  Stream<CambioForo> deLaPublicacion(String publicacionId) =>
      _escuchar('publicacion-$publicacionId', (canal, emitir) {
        canal
          ..onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: _tablaPublicaciones,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: publicacionId,
            ),
            callback: (p) => emitir(_cambio(TablaForo.publicaciones, p)),
          )
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _tablaComentarios,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'publicacion_id',
              value: publicacionId,
            ),
            callback: (p) => emitir(_cambio(TablaForo.comentarios, p)),
          );
      });

  Stream<CambioForo> _escuchar(
    String nombre,
    void Function(RealtimeChannel, void Function(CambioForo?)) configurar,
  ) {
    RealtimeChannel? canal;
    late final StreamController<CambioForo> salida;

    salida = StreamController<CambioForo>(
      onListen: () {
        final abierto = _cliente.channel('foro:$nombre:${_siguienteCanal++}');
        canal = abierto;
        configurar(abierto, (cambio) {
          if (cambio != null && !salida.isClosed) salida.add(cambio);
        });

        var suscritoAntes = false;
        var caido = false;
        abierto.subscribe((estado, error) {
          switch (estado) {
            case RealtimeSubscribeStatus.subscribed:
              // Volvió después de caerse: pudo perderse algo.
              if (suscritoAntes && caido && !salida.isClosed) {
                salida.add(const CambioForo.reconectado());
              }
              suscritoAntes = true;
              caido = false;
            case RealtimeSubscribeStatus.channelError ||
                RealtimeSubscribeStatus.timedOut ||
                RealtimeSubscribeStatus.closed:
              caido = true;
              if (error != null) debugPrint('Realtime del foro: $error');
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

  static CambioForo? _cambio(TablaForo tabla, PostgresChangePayload p) {
    final tipo = switch (p.eventType) {
      PostgresChangeEvent.insert => TipoCambioForo.nuevo,
      PostgresChangeEvent.update => TipoCambioForo.editado,
      // No hay policies de delete: no debería llegar.
      _ => null,
    };
    if (tipo == null) return null;

    final fila = p.newRecord;
    return CambioForo(
      tipo: tipo,
      tabla: tabla,
      id: fila['id'] as String?,
      publicacionId: tabla == TablaForo.comentarios
          ? fila['publicacion_id'] as String?
          : fila['id'] as String?,
      autorId: fila['autor_id'] as String?,
    );
  }
}
