import 'dart:async';

import 'package:traza/services/cambios_foro.dart';

/// Doble de `FuenteCambiosForo`: la prueba decide qué cambios llegan y puede
/// comprobar si alguien sigue escuchando.
class FuenteCambiosForoFalsa implements FuenteCambiosForo {
  late final _foro = StreamController<CambioForo>.broadcast(
    onListen: () => escuchandoForo = true,
    onCancel: () => escuchandoForo = false,
  );
  late final _publicaciones = StreamController<(String, CambioForo)>.broadcast(
    onListen: () => escuchandoPublicacion = true,
    onCancel: () => escuchandoPublicacion = false,
  );

  bool escuchandoForo = false;
  bool escuchandoPublicacion = false;

  @override
  Stream<CambioForo> delForo() => _foro.stream;

  @override
  Stream<CambioForo> deLaPublicacion(String publicacionId) => _publicaciones
      .stream
      .where((evento) => evento.$1 == publicacionId)
      .map((evento) => evento.$2);

  void emitirForo(CambioForo cambio) => _foro.add(cambio);

  void emitirPublicacion(String publicacionId, CambioForo cambio) =>
      _publicaciones.add((publicacionId, cambio));
}
