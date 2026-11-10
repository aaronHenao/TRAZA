import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mapa_progresion.dart';
import 'rutas_oficiales_service.dart';

/// El mapa de progresión del corredor con la sesión abierta: las rutas
/// oficiales y cuáles completó (rutas oficiales, etapa 2).
///
/// Las dos lecturas van una tras otra para que el error que llegue a la
/// pantalla sea el de verdad. `autoDispose`: se consulta de nuevo cada vez
/// que se entra a la pestaña. Si una carrera completa una ruta, lo invalidan
/// el resumen (`SeccionRutaOficial`) o el reenvío de puntos al saberlo
/// (etapa 4).
final mapaProgresionProvider = FutureProvider.autoDispose<MapaProgresion>((
  ref,
) async {
  final repositorio = ref.watch(rutasOficialesRepositoryProvider);
  final oficiales = await repositorio.oficiales();
  final completadas = await repositorio.completadas();

  return MapaProgresion.calcular(
    oficiales: oficiales,
    completadas: completadas,
  );
});
