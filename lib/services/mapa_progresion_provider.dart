import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mapa_progresion.dart';
import 'experiencia_service.dart';
import 'niveles_service.dart';

/// El mapa de progresión del corredor con la sesión abierta (SCRUM-226).
///
/// Las mismas dos lecturas que `progresionProvider`, una tras otra para que
/// el error que llegue a la pantalla sea el de verdad. `autoDispose`: se
/// consulta de nuevo cada vez que se entra a la pestaña, y el cierre del
/// entrenamiento lo invalida para que la nueva posición se vea (criterio 3).
final mapaProgresionProvider = FutureProvider.autoDispose<MapaProgresion>((
  ref,
) async {
  final niveles = await ref.watch(nivelesRepositoryProvider).listar();
  final experiencia = await ref
      .watch(experienciaRepositoryProvider)
      .experienciaAcumulada();

  return MapaProgresion.calcular(experiencia: experiencia, niveles: niveles);
});
