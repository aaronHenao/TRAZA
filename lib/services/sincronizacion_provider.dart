import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_envio_recorrido.dart';
import '../models/recorrido_local.dart';
import 'almacen_recorrido.dart';
import 'entrenamiento_actual_provider.dart';
import 'reenvio_recorridos.dart';

/// Los recorridos de la cuenta que el corredor tiene que ver: los que
/// faltan por subir y los que la base rechazó (Desarrollo Móvil).
///
/// Lo ya subido no sale: el reenvío lo borra del teléfono. Tampoco el del
/// entrenamiento en curso, que se sube por lotes mientras se corre y saldría
/// como pendiente sin que pase nada malo.
final recorridosPorSubirProvider =
    Provider.autoDispose<AsyncValue<List<RecorridoLocal>>>((ref) {
      final enCurso = ref.watch(entrenamientoActualProvider);
      return ref
          .watch(recorridosLocalesProvider)
          .whenData(
            (recorridos) => [
              for (final recorrido in recorridos)
                if (recorrido.entrenamientoId != enCurso &&
                    EstadoEnvioRecorrido.de(recorrido).requiereAtencion)
                  recorrido,
            ],
          );
    });

final sincronizacionRecorridosProvider = Provider<SincronizacionRecorridos>(
  SincronizacionRecorridos.new,
);

/// Lo que el corredor puede hacer con un recorrido que no subió: volver a
/// intentarlo o, si la base lo rechazó, descartarlo (sección 8 de los
/// lineamientos de Desarrollo Móvil).
///
/// No sabe cómo se sube ni cómo se guarda: reintentar es el mismo reenvío del
/// arranque (`reenvioRecorridosProvider`) y descartar es olvidar el recorrido
/// en el almacén de Drift.
class SincronizacionRecorridos {
  const SincronizacionRecorridos(this._ref);

  final Ref _ref;

  static const sinSubir = 'No se pudo subir. Revisa tu conexión';
  static const descartado = 'Recorrido descartado';
  static const noSeDescarto = 'No se pudo descartar el recorrido';

  static String subidos(int cuantos) =>
      cuantos == 1 ? 'Se subió 1 recorrido' : 'Se subieron $cuantos recorridos';

  /// Vuelve a intentar subir lo pendiente de la cuenta. Devuelve cuántos
  /// recorridos quedaron completos.
  ///
  /// Lo que falle se queda en el teléfono con su motivo: la lista lo muestra
  /// sola, porque Drift avisa de cada cambio.
  Future<int> reintentar() async {
    try {
      // `refresh` lo vuelve a correr una sola vez, aunque la portada también
      // lo esté mirando.
      return await _ref.refresh(reenvioRecorridosProvider.future);
    } catch (error) {
      debugPrint('No se pudo reintentar la subida: ${error.runtimeType}');
      return 0;
    }
  }

  /// Borra del teléfono el recorrido de [entrenamientoId] y sus puntos. Es
  /// para lo que la base rechazó: el entrenamiento en Supabase no cambia.
  Future<bool> descartar(String entrenamientoId) async {
    try {
      await _ref.read(almacenRecorridoProvider).olvidar(entrenamientoId);
      return true;
    } catch (error) {
      // Solo el tipo: el error de SQLite puede traer la fila, con su
      // ubicación.
      debugPrint('No se pudo descartar el recorrido: ${error.runtimeType}');
      return false;
    }
  }
}
