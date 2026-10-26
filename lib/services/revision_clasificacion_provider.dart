import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rutas_service.dart';

/// Si la cuenta con la sesión abierta puede revisar la clasificación de una
/// ruta (SCRUM-261, criterio 1 de HU-35).
///
/// Se lo pregunta a la base (`puede_revisar_clasificacion`, 0042), que es la
/// que tiene la regla: Runner Experto y no autor. Decide qué se muestra;
/// lo que de verdad se pueda guardar lo deciden los permisos de la base.
final puedeRevisarClasificacionProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, rutaId) =>
          ref.watch(rutasRepositoryProvider).puedeRevisarClasificacion(rutaId),
    );
