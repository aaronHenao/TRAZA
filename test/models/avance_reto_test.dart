import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/avance_reto.dart';
import 'package:traza/models/experiencia_ganada.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/regla_experiencia.dart';
import 'package:traza/models/resumen_entrenamiento.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/vigencia_reto.dart';

/// Pruebas de cuánto avanzó cada reto con el entrenamiento recién finalizado:
/// la misma regla que `otorgar_experiencia()` aplica en la base.
void main() {
  const correr = TipoActividad(id: 'tipo-correr', nombre: 'Correr');
  const caminar = TipoActividad(id: 'tipo-caminar', nombre: 'Caminar');
  final fin = DateTime(2026, 10, 16, 18);

  const sinRetos = ExperienciaDeEntrenamiento(
    xpActividad: 0,
    ajuste: AjusteExperiencia.ninguno,
  );

  ResumenEntrenamiento resumen({double? metros = 2500}) => ResumenEntrenamiento(
    entrenamientoId: 'e-1',
    nombreActividad: 'Correr',
    fechaFin: fin,
    duracion: const Duration(minutes: 15),
    distanciaMetros: metros,
  );

  RetoDelUsuario mio({
    String id = 'r1',
    TipoActividad tipo = correr,
    double metaKm = 10,
    double progresoKm = 5,
    EstadoRetoUsuario estado = EstadoRetoUsuario.enProgreso,
    EstadoReto estadoReto = EstadoReto.activo,
    DateTime? inicio,
    DateTime? finVigencia,
    DateTime? activacion,
  }) => RetoDelUsuario(
    reto: Reto(
      id: id,
      nombre: 'Reto $id',
      descripcion: 'Prueba',
      periodicidad: PeriodicidadReto.semanal,
      metaKm: metaKm,
      xpOtorgada: 200,
      vigencia: VigenciaReto(
        inicio: inicio ?? DateTime(2026, 10, 12),
        fin: finVigencia ?? DateTime(2026, 10, 18),
      ),
      estado: estadoReto,
      tipoActividad: tipo,
    ),
    estado: estado,
    progresoKm: progresoKm,
    fechaActivacion: activacion ?? DateTime(2026, 10, 12, 8),
  );

  List<AvanceReto> avances(
    List<RetoDelUsuario> misRetos, {
    ExperienciaDeEntrenamiento xp = sinRetos,
    double? metros = 2500,
  }) => AvanceReto.delEntrenamiento(
    misRetos: misRetos,
    xp: xp,
    resumen: resumen(metros: metros),
  );

  test('un reto en curso de la misma actividad avanza con los km', () {
    final [avance] = avances([mio(progresoKm: 5)]);

    expect(avance.kmAportados, 2.5);
    expect(avance.kmAntes, 2.5);
    expect(avance.progresoAntes, 0.25);
    expect(avance.progresoDespues, 0.5);
    expect(avance.completadoAhora, isFalse);
  });

  test('un reto de otra actividad no avanza', () {
    expect(avances([mio(tipo: caminar)]), isEmpty);
  });

  test('un reto fuera de su vigencia no avanza', () {
    expect(
      avances([
        mio(inicio: DateTime(2026, 10, 1), finVigencia: DateTime(2026, 10, 15)),
      ]),
      isEmpty,
    );
  });

  test('un reto activado después de finalizar no avanza', () {
    expect(avances([mio(activacion: DateTime(2026, 10, 16, 19))]), isEmpty);
  });

  test('un reto retirado no avanza', () {
    expect(avances([mio(estadoReto: EstadoReto.retirado)]), isEmpty);
  });

  test('un reto completado antes no aparece', () {
    expect(
      avances([mio(estado: EstadoRetoUsuario.completado, progresoKm: 12)]),
      isEmpty,
    );
  });

  test('el reto que completó trae la XP que pagó', () {
    final [avance] = avances(
      [mio(estado: EstadoRetoUsuario.completado, progresoKm: 10.5)],
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 0,
        ajuste: AjusteExperiencia.ninguno,
        retos: [RetoCompletado(nombre: 'Reto r1', xp: 200, retoId: 'r1')],
      ),
    );

    expect(avance.completadoAhora, isTrue);
    expect(avance.xpGanada, 200);
    expect(avance.kmAntes, 8);
    expect(avance.progresoDespues, 1);
  });

  test('si los km no contaron, ningún reto avanzó', () {
    for (final ajuste in [
      AjusteExperiencia.velocidadImposible,
      AjusteExperiencia.sinDatos,
    ]) {
      expect(
        avances([
          mio(),
        ], xp: ExperienciaDeEntrenamiento(xpActividad: 0, ajuste: ajuste)),
        isEmpty,
        reason: ajuste.name,
      );
    }
  });

  test('sin distancia no avanza nada', () {
    expect(avances([mio()], metros: null), isEmpty);
    expect(avances([mio()], metros: 0), isEmpty);
  });

  test('lo de antes no baja de cero', () {
    // Un progreso menor que los km del entrenamiento solo puede venir de un
    // dato raro; la barra no debe empezar en negativo.
    final [avance] = avances([mio(progresoKm: 1)]);

    expect(avance.kmAntes, 0);
    expect(avance.progresoAntes, 0);
  });

  test('los completados van primero y luego los más cerca de la meta', () {
    final lista = avances(
      [
        mio(id: 'lejos', progresoKm: 3),
        mio(id: 'cerca', progresoKm: 9),
        mio(id: 'hecho', estado: EstadoRetoUsuario.completado, progresoKm: 11),
      ],
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 0,
        ajuste: AjusteExperiencia.ninguno,
        retos: [RetoCompletado(nombre: 'Reto hecho', xp: 200, retoId: 'hecho')],
      ),
    );

    expect(lista.map((avance) => avance.reto.reto.id), [
      'hecho',
      'cerca',
      'lejos',
    ]);
  });
}
