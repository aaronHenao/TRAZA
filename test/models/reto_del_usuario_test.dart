import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/tipo_actividad.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/models/vigencia_reto.dart';

/// Pruebas de lo que el corredor lleva con cada reto: cómo se lee de la base,
/// cuándo cuenta como vencido (SCRUM-173) y cómo se reparte por las pestañas
/// del historial (SCRUM-174).
void main() {
  final hoy = DateTime(2026, 9, 28, 10);

  Reto reto({
    String id = 'r1',
    double metaKm = 15,
    DateTime? inicio,
    DateTime? fin,
  }) => Reto(
    id: id,
    nombre: 'Corre 15 km esta semana',
    descripcion: 'Suma 15 km entre lunes y domingo.',
    periodicidad: PeriodicidadReto.semanal,
    metaKm: metaKm,
    xpOtorgada: 200,
    vigencia: VigenciaReto(
      inicio: inicio ?? DateTime(2026, 9, 28),
      fin: fin ?? DateTime(2026, 10, 4),
    ),
    estado: EstadoReto.activo,
    tipoActividad: const TipoActividad(id: 'tipo-correr', nombre: 'Correr'),
  );

  RetoDelUsuario mio({
    Reto? elReto,
    EstadoRetoUsuario estado = EstadoRetoUsuario.enProgreso,
    double progresoKm = 5,
    DateTime? fechaCompletado,
  }) => RetoDelUsuario(
    reto: elReto ?? reto(),
    estado: estado,
    progresoKm: progresoKm,
    fechaActivacion: DateTime(2026, 9, 28, 8),
    fechaCompletado: fechaCompletado,
  );

  group('progreso', () {
    test('es la parte de la meta que lleva', () {
      expect(mio(progresoKm: 3).progreso, 0.2);
    });

    test('pasarse de la meta llena la barra, no la desborda', () {
      expect(mio(progresoKm: 30).progreso, 1);
    });

    test('sin empezar es cero', () {
      expect(mio(progresoKm: 0).progreso, 0);
    });

    test('una meta en cero no revienta la división', () {
      expect(mio(elReto: reto(metaKm: 0), progresoKm: 5).progreso, 0);
    });
  });

  group('vencido (SCRUM-173)', () {
    test('lo que sigue en progreso con la vigencia pasada está vencido', () {
      final caducado = mio(
        elReto: reto(inicio: DateTime(2026, 9, 14), fin: DateTime(2026, 9, 20)),
      );

      expect(caducado.vencidoEn(hoy), isTrue);
      expect(caducado.enCursoEn(hoy), isFalse);
    });

    test('se deduce del calendario aunque la fila no diga vencido', () {
      // Marcar la fila exigiría un proceso que recorra la tabla cada noche, y
      // ese proceso no existe: el calendario sí está siempre al día.
      final caducado = mio(
        estado: EstadoRetoUsuario.enProgreso,
        elReto: reto(fin: DateTime(2026, 9, 20)),
      );

      expect(caducado.vencidoEn(hoy), isTrue);
    });

    test('si la fila ya dice vencido, se respeta', () {
      expect(mio(estado: EstadoRetoUsuario.vencido).vencidoEn(hoy), isTrue);
    });

    test('el último día todavía cuenta como en curso', () {
      final ultimoDia = mio(elReto: reto(fin: DateTime(2026, 9, 28)));

      expect(ultimoDia.vencidoEn(hoy), isFalse);
      expect(ultimoDia.enCursoEn(hoy), isTrue);
    });

    test('lo completado nunca se vence, aunque la vigencia pasara', () {
      final completado = mio(
        estado: EstadoRetoUsuario.completado,
        elReto: reto(fin: DateTime(2026, 9, 20)),
        fechaCompletado: DateTime(2026, 9, 19),
      );

      expect(completado.vencidoEn(hoy), isFalse);
      expect(completado.enCursoEn(hoy), isFalse);
    });
  });

  group('secciones del historial', () {
    final enCurso = mio();
    final completado = mio(
      elReto: reto(id: 'r2'),
      estado: EstadoRetoUsuario.completado,
      progresoKm: 15,
      fechaCompletado: DateTime(2026, 9, 27),
    );
    final vencido = mio(
      elReto: reto(id: 'r3', fin: DateTime(2026, 9, 20)),
      progresoKm: 2,
    );
    final todos = [enCurso, completado, vencido];

    test('cada reto cae en una sola', () {
      expect(SeccionHistorialRetos.enCurso.filtrar(todos, hoy), [enCurso]);
      expect(SeccionHistorialRetos.completados.filtrar(todos, hoy), [
        completado,
      ]);
      expect(SeccionHistorialRetos.vencidos.filtrar(todos, hoy), [vencido]);
    });

    test('entre las tres no se pierde ni se repite ninguno', () {
      final repartidos = [
        for (final seccion in SeccionHistorialRetos.values)
          ...seccion.filtrar(todos, hoy),
      ];

      expect(repartidos, hasLength(todos.length));
      expect(repartidos.toSet(), todos.toSet());
    });

    test('cada pestaña vacía dice lo suyo', () {
      // Un mensaje común obligaría a mirar qué chip está activo para saber de
      // qué habla.
      final titulos = SeccionHistorialRetos.values
          .map((seccion) => seccion.tituloVacio)
          .toSet();

      expect(titulos, hasLength(SeccionHistorialRetos.values.length));
    });
  });

  group('lectura de una fila de retos_usuario', () {
    final fila = {
      'id': 'ru1',
      'estado': 'completado',
      'progreso_km': 15,
      'fecha_activacion': '2026-09-27T08:00:00Z',
      'fecha_completado': '2026-09-27T19:30:00Z',
      'retos': {
        'id': 'r1',
        'nombre': 'Corre 15 km esta semana',
        'descripcion': 'Suma 15 km entre lunes y domingo.',
        'periodicidad': 'semanal',
        'meta_km': 15,
        'xp_otorgada': 200,
        'fecha_inicio': '2026-09-21',
        'fecha_fin': '2026-09-27',
        'estado': 'activo',
        'tipo_actividad_id': 'tipo-correr',
        'tipos_actividad': {'nombre': 'Correr'},
      },
    };

    test('trae el reto embebido', () {
      final leido = RetoDelUsuario.desdeSupabase(fila);

      expect(leido.reto.nombre, 'Corre 15 km esta semana');
      expect(leido.reto.metaKm, 15);
      expect(leido.estado, EstadoRetoUsuario.completado);
      expect(leido.progresoKm, 15);
      expect(leido.completado, isTrue);
    });

    test('sin fecha de completado queda en nulo', () {
      final leido = RetoDelUsuario.desdeSupabase({
        ...fila,
        'estado': 'en_progreso',
        'fecha_completado': null,
      });

      expect(leido.fechaCompletado, isNull);
      expect(leido.completado, isFalse);
    });

    test('una fila incompleta falla en vez de inventarse valores', () {
      expect(
        () => RetoDelUsuario.desdeSupabase({...fila}..remove('retos')),
        throwsFormatException,
      );
      expect(
        () => RetoDelUsuario.desdeSupabase({...fila, 'estado': 'abandonado'}),
        throwsFormatException,
      );
    });
  });
}
