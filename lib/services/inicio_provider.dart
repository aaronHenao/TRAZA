import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/resumen_entrenamiento.dart';
import '../models/resumen_semana.dart';
import '../models/tipo_objetivo.dart';
import 'auth_service.dart';
import 'historial_service.dart';
import 'objetivos_service.dart';
import 'reloj_provider.dart';

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

/// Los últimos entrenamientos, para asomarlos en la portada.
final ultimosEntrenamientosProvider =
    FutureProvider.autoDispose<List<ResumenEntrenamiento>>((ref) async {
      final historial = await ref.watch(historialProvider.future);
      return historial.take(cuantosUltimosEnPortada).toList();
    });
