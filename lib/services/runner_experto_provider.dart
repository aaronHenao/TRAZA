import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/runner_experto.dart';
import 'auth_service.dart';
import 'experiencia_service.dart';
import 'objetivos_service.dart' show SesionRequeridaException;
import 'reloj_provider.dart';

/// El estado del corredor con la sesión abierta frente a Runner Experto
/// (SCRUM-211).
///
/// `autoDispose`: se consulta de nuevo cada vez que se entra a la pantalla,
/// así la XP ganada desde la última visita ya cuenta.
final estadoRunnerExpertoProvider =
    FutureProvider.autoDispose<EstadoRunnerExperto>((ref) async {
      final fechaRegistro = ref.watch(authServiceProvider).fechaCreacionCuenta;
      if (fechaRegistro == null) throw const SesionRequeridaException();

      final experiencia = await ref
          .watch(experienciaRepositoryProvider)
          .experienciaAcumulada();

      return EstadoRunnerExperto.calcular(
        experiencia: experiencia,
        fechaRegistro: fechaRegistro,
        ahora: ref.read(relojProvider)(),
      );
    });
