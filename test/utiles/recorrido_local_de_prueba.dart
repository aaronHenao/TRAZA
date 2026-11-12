import 'package:traza/models/recorrido_local.dart';

/// Un recorrido guardado en el teléfono, para las pruebas de la pantalla de
/// sincronización. Por defecto, pendiente de subir y sin errores.
RecorridoLocal recorridoLocalDePrueba(
  String entrenamientoId, {
  bool pendienteSync = true,
  String? ultimoError,
  bool rechazado = false,
  int puntosSinEnviar = 3,
  DateTime? actualizadoEn,
}) => RecorridoLocal(
  entrenamientoId: entrenamientoId,
  usuarioId: 'usuario-1',
  actualizadoEn: actualizadoEn ?? DateTime(2026, 11, 11, 9),
  pendienteSync: pendienteSync,
  ultimoError: ultimoError,
  rechazado: rechazado,
  puntosSinEnviar: puntosSinEnviar,
);

/// Uno que la red no dejó subir.
RecorridoLocal recorridoFallidoDePrueba(String entrenamientoId) =>
    recorridoLocalDePrueba(
      entrenamientoId,
      ultimoError: RecorridoLocal.motivoSinEnviar,
    );

/// Uno que la base no acepta: el entrenamiento no existe o es de otra
/// cuenta.
RecorridoLocal recorridoRechazadoDePrueba(String entrenamientoId) =>
    recorridoLocalDePrueba(
      entrenamientoId,
      ultimoError: RecorridoLocal.motivoRechazado,
      rechazado: true,
    );

/// Uno que ya subió entero y el teléfono todavía no ha borrado.
RecorridoLocal recorridoSubidoDePrueba(String entrenamientoId) =>
    recorridoLocalDePrueba(
      entrenamientoId,
      pendienteSync: false,
      puntosSinEnviar: 0,
    );
