import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// De dónde salen los avisos de cambios del foro. Las pruebas lo sustituyen
/// con `overrideWithValue`.
final fuenteCambiosForoProvider = Provider<FuenteCambiosForo>(
  (ref) => SupabaseCambiosForo(),
);

/// Qué tabla cambió. `moderaciones` es `moderaciones_foro` (SCRUM-322).
enum TablaForo { publicaciones, comentarios, moderaciones }

/// Qué pasó.
enum TipoCambioForo {
  /// Se insertó una fila, o la moderación aprobó una publicación: para quien
  /// lee el foro, apareció (SCRUM-322).
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
    this.estado,
    this.motivo,
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

  /// Cómo quedó la fila, tal como lo guarda la base (`publicada`,
  /// `rechazada`...).
  final String? estado;

  /// En una moderación, por qué se rechazó.
  final String? motivo;

  bool get esPublicacionNueva =>
      tipo == TipoCambioForo.nuevo && tabla == TablaForo.publicaciones;

  /// La moderación rechazó algo (criterio 5 de SCRUM-322).
  bool get esRechazo =>
      tabla == TablaForo.moderaciones &&
      tipo == TipoCambioForo.editado &&
      estado == 'rechazada';

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
  static const _tablaModeraciones = 'moderaciones_foro';

  @override
  Stream<CambioForo> delForo() => _escuchar('foro', (canal, emitir) {
    canal
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: _tablaPublicaciones,
        callback: (p) => emitir(_cambio(TablaForo.publicaciones, p)),
      )
      // En el listado se ve cuántos comentarios hay, no lo que dicen: basta
      // con los nuevos y con los que la moderación aprobó.
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: _tablaComentarios,
        callback: (p) => emitir(_cambio(TablaForo.comentarios, p)),
      )
      // SCRUM-322: al autor le llegan los veredictos de lo suyo; al
      // administrador, todos (la policy de select decide).
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: _tablaModeraciones,
        callback: (p) => emitir(_cambio(TablaForo.moderaciones, p)),
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
          )
          // SCRUM-322: las ediciones propias de la publicación o de sus
          // comentarios que esperan la moderación.
          ..onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _tablaModeraciones,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'publicacion_id',
              value: publicacionId,
            ),
            callback: (p) => emitir(_cambio(TablaForo.moderaciones, p)),
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
    final fila = p.newRecord;
    return cambioDesdeFila(tabla, switch (p.eventType) {
      PostgresChangeEvent.insert => TipoCambioForo.nuevo,
      PostgresChangeEvent.update => TipoCambioForo.editado,
      // No hay policies de delete: no debería llegar.
      _ => null,
    }, fila);
  }

  /// Traduce la fila que llegó por Realtime. Separado de `_cambio` para
  /// probarlo sin un canal de verdad.
  @visibleForTesting
  static CambioForo? cambioDesdeFila(
    TablaForo tabla,
    TipoCambioForo? tipo,
    Map<String, dynamic> fila,
  ) {
    if (tipo == null) return null;
    final estado = fila['estado'] as String?;

    // SCRUM-322: una publicación que pasa a publicada sin haber sido editada
    // nunca es una que la moderación acaba de aprobar. Para el foro es nueva,
    // aunque en la base sea un update. Una edición aprobada trae
    // `fecha_edicion` y sigue siendo una edición.
    final aprobada =
        tabla == TablaForo.publicaciones &&
        tipo == TipoCambioForo.editado &&
        estado == 'publicada' &&
        fila['fecha_edicion'] == null;

    return CambioForo(
      tipo: aprobada ? TipoCambioForo.nuevo : tipo,
      tabla: tabla,
      id: fila['id'] as String?,
      publicacionId: tabla == TablaForo.publicaciones
          ? fila['id'] as String?
          : fila['publicacion_id'] as String?,
      autorId: fila['autor_id'] as String?,
      estado: estado,
      motivo: fila['motivo'] as String?,
    );
  }
}
