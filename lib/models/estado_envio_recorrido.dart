import 'recorrido_local.dart';

/// En qué va la subida de un recorrido guardado en el teléfono, como lo ve
/// el corredor en la pantalla de sincronización (Desarrollo Móvil).
///
/// Es aparte del estado del entrenamiento: el entrenamiento ya quedó
/// finalizado en la base, y lo que puede faltar es subir los puntos de su
/// recorrido. Por eso la pantalla dice las dos cosas por separado.
enum EstadoEnvioRecorrido {
  /// Falta subir algo y todavía no ha fallado: se sube solo con conexión.
  pendiente('Pendiente de subir'),

  /// El último intento falló, casi siempre por la red. Se puede reintentar.
  fallido('No se pudo subir'),

  /// La base no lo acepta: reintentar no lo arregla, solo queda descartarlo.
  rechazado('Rechazado por la base'),

  /// Ya está entero en la base; el teléfono lo borra en el próximo reenvío.
  subido('Subido');

  const EstadoEnvioRecorrido(this.etiqueta);

  final String etiqueta;

  /// El estado de [recorrido]. El rechazo pesa más que el error, y el error
  /// más que lo pendiente: es el orden en que el corredor tiene que actuar.
  static EstadoEnvioRecorrido de(RecorridoLocal recorrido) {
    if (recorrido.rechazado) return rechazado;
    if (recorrido.ultimoError != null) return fallido;
    if (recorrido.pendienteSync || recorrido.puntosSinEnviar > 0) {
      return pendiente;
    }
    return subido;
  }

  /// Si el corredor tiene que enterarse: todo menos lo que ya subió.
  bool get requiereAtencion => this != subido;

  /// Si "Reintentar" puede arreglarlo. Lo rechazado no: la base lo volvería
  /// a rechazar.
  bool get reintentable => this == pendiente || this == fallido;
}
