import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rutas_service.dart';

/// Si la cuenta con la sesión abierta puede revisar la clasificación de una
/// ruta (SCRUM-261, criterio 1 de HU-35).
///
/// Se lo pregunta a la base (`puede_revisar_clasificacion`, 0042 y 0054), que
/// es la que tiene la regla: el Runner Experto que la clasificó, con la ruta
/// ya publicada y sin revisar. Decide qué se muestra; lo que de verdad se
/// pueda guardar lo deciden los permisos de la base.
final puedeRevisarClasificacionProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, rutaId) =>
          ref.watch(rutasRepositoryProvider).puedeRevisarClasificacion(rutaId),
    );

/// Cuándo se revisó la clasificación de una ruta, o null si nadie la ha
/// revisado (SCRUM-264, criterio 5 de HU-35).
///
/// Va aparte de la ruta: la revisión vive en su propia tabla (0054), y así
/// las consultas de la ruta no cambian.
final clasificacionRevisadaEnProvider = FutureProvider.autoDispose
    .family<DateTime?, String>(
      (ref, rutaId) =>
          ref.watch(rutasRepositoryProvider).clasificacionRevisadaEn(rutaId),
    );
