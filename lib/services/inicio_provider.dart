import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/resumen_entrenamiento.dart';
import '../models/resumen_semana.dart';
import '../models/reto_del_usuario.dart';
import '../models/tipo_objetivo.dart';
import 'auth_service.dart';
import 'historial_service.dart';
import 'objetivos_service.dart';
import 'reloj_provider.dart';
import 'retos_provider.dart';

/// Nombre con el que saludar en la portada, o null si no hay ninguno.
final nombreUsuarioProvider = Provider<String?>(
  (ref) => ref.watch(authServiceProvider).nombreUsuario,
);

/// Cuántos entrenamientos se asoman en la portada antes de mandar al
/// historial completo.
const cuantosUltimosEnPortada = 3;

/// Lo que el usuario lleva esta semana, para la portada.
///
/// Junta sus entrenamientos con el objetivo de distancia del perfil. Si los
/// objetivos no se pueden leer, el resumen igual se muestra sin meta: es peor
/// dejar la portada en blanco por eso.
final resumenSemanaProvider = FutureProvider.autoDispose<ResumenSemana>((
  ref,
) async {
  final historial = await ref.watch(historialProvider.future);
  return ResumenSemana.desde(
    historial,
    ahora: ref.read(relojProvider)(),
    metaKilometros: await ref.watch(metaSemanalProvider.future),
  );
});

/// Objetivo de distancia semanal del perfil, o null si no lo configuró o no se
/// pudo leer.
final metaSemanalProvider = FutureProvider.autoDispose<num?>((ref) async {
  try {
    final objetivos = await ref.watch(objetivosRepositoryProvider).cargar();
    return objetivos[TipoObjetivo.distancia];
  } catch (_) {
    return null;
  }
});

/// Los retos que el corredor tiene en juego ahora mismo, para la portada
/// (SCRUM-287 y SCRUM-288).
///
/// En juego es lo mismo que en la sección de Retos: activados, sin completar y
/// con la vigencia abierta. El filtro se hace aquí y no en la base para no
/// repetir la regla: la de `RetoDelUsuario` es la que manda.
///
/// Van del que se acaba primero al que más plazo le queda, y entre los que
/// terminan el mismo día, el más avanzado delante: así el que la portada
/// destaca es el que hay que atender hoy.
final retosEnCursoProvider = FutureProvider.autoDispose<List<RetoDelUsuario>>((
  ref,
) async {
  final mios = await ref.watch(misRetosProvider.future);
  final ahora = ref.read(relojProvider)();

  return mios.where((mio) => mio.enCursoEn(ahora)).toList()..sort((a, b) {
    final plazo = a.reto.vigencia
        .diasRestantesDesde(ahora)
        .compareTo(b.reto.vigencia.diasRestantesDesde(ahora));
    return plazo != 0 ? plazo : b.progreso.compareTo(a.progreso);
  });
});

/// Los últimos entrenamientos, para asomarlos en la portada.
final ultimosEntrenamientosProvider =
    FutureProvider.autoDispose<List<ResumenEntrenamiento>>((ref) async {
      final historial = await ref.watch(historialProvider.future);
      return historial.take(cuantosUltimosEnPortada).toList();
    });
