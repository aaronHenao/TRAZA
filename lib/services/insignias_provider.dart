import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/insignia.dart';
import 'insignias_service.dart';

/// Las insignias del corredor con la sesión abierta (SCRUM-193).
///
/// `autoDispose`, como la progresión: se consulta de nuevo cada vez que se
/// entra a la pantalla, así las que otorgó el trigger desde la última visita
/// se ven sin trucos.
final insigniasProvider = FutureProvider.autoDispose<List<Insignia>>(
  (ref) => ref.watch(insigniasRepositoryProvider).listar(),
);
