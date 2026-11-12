import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/estado_envio_recorrido.dart';

import '../utiles/recorrido_local_de_prueba.dart';

void main() {
  test('lo que falta por subir y no ha fallado está pendiente', () {
    expect(
      EstadoEnvioRecorrido.de(recorridoLocalDePrueba('ent-1')),
      EstadoEnvioRecorrido.pendiente,
    );
  });

  test('si el último intento falló, se ve como fallido', () {
    expect(
      EstadoEnvioRecorrido.de(recorridoFallidoDePrueba('ent-1')),
      EstadoEnvioRecorrido.fallido,
    );
  });

  test('el rechazo de la base pesa más que el error', () {
    expect(
      EstadoEnvioRecorrido.de(recorridoRechazadoDePrueba('ent-1')),
      EstadoEnvioRecorrido.rechazado,
    );
  });

  test('lo que ya subió entero no pide atención', () {
    final estado = EstadoEnvioRecorrido.de(recorridoSubidoDePrueba('ent-1'));

    expect(estado, EstadoEnvioRecorrido.subido);
    expect(estado.requiereAtencion, isFalse);
  });

  test('reintentar sirve para lo pendiente y lo fallido, no para lo '
      'rechazado', () {
    expect(EstadoEnvioRecorrido.pendiente.reintentable, isTrue);
    expect(EstadoEnvioRecorrido.fallido.reintentable, isTrue);
    expect(EstadoEnvioRecorrido.rechazado.reintentable, isFalse);
    expect(EstadoEnvioRecorrido.subido.reintentable, isFalse);
  });
}
