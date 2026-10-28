import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/resumen_entrenamiento.dart';
import '../models/resumen_semana.dart';
import '../models/reto_del_usuario.dart';
import '../models/ruta.dart';
import '../models/tipo_objetivo.dart';
import 'auth_service.dart';
import 'historial_service.dart';
import 'objetivos_service.dart';
import 'reloj_provider.dart';
import 'retos_provider.dart';
import 'rutas_provider.dart';

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

/// Cuántas rutas se asoman en el carrusel de la portada antes de mandar a la
/// sección de Rutas.
const cuantasRutasEnPortada = 5;

/// Las rutas que la portada asoma en su carrusel (SCRUM-289).
///
/// Deberían ser las más cercanas, pero la cercanía la produce HU-29
/// (SCRUM-243): necesita el permiso de ubicación y la distancia del usuario a
/// cada trazado, que todavía no se calcula. Hasta entonces son las últimas
/// publicadas, que es lo que la comunidad tiene hoy. Cuando HU-29 llegue, el
/// orden cambia aquí y el carrusel se queda igual.
final rutasCercanasProvider = FutureProvider.autoDispose<List<Ruta>>((
  ref,
) async {
  final publicadas = await ref.watch(rutasPublicadasProvider.future);

  return publicadas.take(cuantasRutasEnPortada).toList();
});

/// Los últimos entrenamientos, para asomarlos en la portada.
final ultimosEntrenamientosProvider =
    FutureProvider.autoDispose<List<ResumenEntrenamiento>>((ref) async {
      final historial = await ref.watch(historialProvider.future);
      return historial.take(cuantosUltimosEnPortada).toList();
    });
