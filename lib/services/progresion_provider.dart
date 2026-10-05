import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/progresion.dart';
import 'experiencia_service.dart';
import 'niveles_service.dart';

/// La progresión del corredor con la sesión abierta (SCRUM-186).
///
/// Junta las dos piezas que ya existen —los umbrales que registró el
/// administrador (SCRUM-177) y la experiencia que acredita el motor de
/// experiencia— y las ubica una respecto de la otra. No suma XP ni la deduce
/// de los entrenamientos: si el valor acumulado cambia, es porque quien lo
/// persiste lo cambió.
///
/// Las dos consultas van una tras otra, sin agruparlas, para que el error que
/// llegue a la pantalla sea el de verdad —quedarse sin sesión, por ejemplo— y
/// no uno envuelto que haya que desempaquetar para saber qué pasó.
///
/// `autoDispose`: se consulta de nuevo cada vez que se entra a la pantalla,
/// así la experiencia ganada desde la última visita se ve sin trucos
/// (criterio 5 de SCRUM-178).
final progresionProvider = FutureProvider.autoDispose<Progresion>((ref) async {
  final niveles = await ref.watch(nivelesRepositoryProvider).listar();
  final experiencia = await ref
      .watch(experienciaRepositoryProvider)
      .experienciaAcumulada();

  return Progresion.calcular(experiencia: experiencia, niveles: niveles);
});
