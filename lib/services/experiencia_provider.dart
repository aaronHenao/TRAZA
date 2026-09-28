import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/experiencia_ganada.dart';
import 'experiencia_service.dart';

/// La XP que dejó un entrenamiento finalizado, para su resumen (SCRUM-207).
///
/// Se lee de la base por id, no de un estado en memoria: así también sale al
/// abrir el resumen desde el historial.
final experienciaDeEntrenamientoProvider = FutureProvider.autoDispose
    .family<ExperienciaDeEntrenamiento?, String>(
      (ref, entrenamientoId) =>
          ref.watch(experienciaRepositoryProvider).ganadaEn(entrenamientoId),
    );
