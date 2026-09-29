import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ascenso.dart';
import '../models/experiencia_ganada.dart';
import '../models/progresion.dart';
import 'experiencia_service.dart';
import 'niveles_service.dart';

/// La XP que dejó un entrenamiento finalizado, para su resumen (SCRUM-207).
///
/// Se lee de la base por id, no de un estado en memoria: así también sale al
/// abrir el resumen desde el historial.
final experienciaDeEntrenamientoProvider = FutureProvider.autoDispose
    .family<ExperienciaDeEntrenamiento?, String>(
      (ref, entrenamientoId) =>
          ref.watch(experienciaRepositoryProvider).ganadaEn(entrenamientoId),
    );

/// El nivel del usuario visto desde el resumen de un entrenamiento
/// (SCRUM-198) y, si ese entrenamiento lo hizo subir, el ascenso
/// (SCRUM-197).
typedef NivelTrasEntrenamiento = ({Progresion progresion, Ascenso? ascenso});

/// Calcula [NivelTrasEntrenamiento] sin guardar nada nuevo: la XP de antes es
/// la acumulada menos la que dejó este entrenamiento.
///
/// Esa resta solo vale justo después de finalizar. Abierto desde el
/// historial, la XP ganada después la falsearía: ahí el resumen no anuncia el
/// ascenso (ver `SeccionExperiencia.anunciarAscenso`).
final nivelTrasEntrenamientoProvider = FutureProvider.autoDispose
    .family<NivelTrasEntrenamiento, String>((ref, entrenamientoId) async {
      final ganada = await ref.watch(
        experienciaDeEntrenamientoProvider(entrenamientoId).future,
      );
      final niveles = await ref.watch(nivelesRepositoryProvider).listar();
      final despues = await ref
          .watch(experienciaRepositoryProvider)
          .experienciaAcumulada();

      final xpGanada = ganada?.total ?? 0;
      return (
        progresion: Progresion.calcular(experiencia: despues, niveles: niveles),
        ascenso: xpGanada == 0
            ? null
            : Ascenso.entre(
                xpAntes: despues - xpGanada,
                xpDespues: despues,
                niveles: niveles,
              ),
      );
    });
