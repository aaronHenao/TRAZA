import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/estado_cronometro.dart';
import 'package:traza/services/cronometro_service.dart';

import '../utiles/reloj_falso.dart';

void main() {
  late RelojFalso reloj;
  late CronometroService cronometro;

  setUp(() {
    reloj = RelojFalso();
    cronometro = CronometroService(reloj: reloj.call);
  });

  group('CronometroService', () {
    test('antes de iniciar está detenido y en cero', () {
      expect(cronometro.transcurrido, Duration.zero);
      expect(cronometro.marcha, MarchaCronometro.detenido);
      expect(cronometro.estado.tiempoFormateado, '00:00:00');
    });

    test('iniciar arranca desde cero y deja la actividad en curso', () {
      cronometro.iniciar();

      expect(cronometro.transcurrido, Duration.zero);
      expect(cronometro.marcha, MarchaCronometro.enCurso);
      expect(cronometro.estado.tiempoFormateado, '00:00:00');
    });

    test('iniciar de nuevo descarta el tiempo de la actividad anterior', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(minutes: 12));
      expect(cronometro.transcurrido, const Duration(minutes: 12));

      cronometro.iniciar();

      expect(cronometro.transcurrido, Duration.zero);
    });

    test('el tiempo avanza mientras la actividad está en curso', () {
      cronometro.iniciar();

      reloj.avanzar(const Duration(seconds: 1));
      expect(cronometro.estado.tiempoFormateado, '00:00:01');

      reloj.avanzar(const Duration(seconds: 64));
      expect(cronometro.estado.tiempoFormateado, '00:01:05');

      reloj.avanzar(const Duration(hours: 1));
      expect(cronometro.estado.tiempoFormateado, '01:01:05');
    });

    test('pausar congela el tiempo transcurrido', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(seconds: 30));

      cronometro.pausar();
      reloj.avanzar(const Duration(minutes: 5));

      expect(cronometro.transcurrido, const Duration(seconds: 30));
      expect(cronometro.marcha, MarchaCronometro.pausado);
    });

    test('reanudar sigue contando desde donde iba', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(seconds: 30));
      cronometro.pausar();
      reloj.avanzar(const Duration(minutes: 5));

      cronometro.reanudar();
      reloj.avanzar(const Duration(seconds: 10));

      expect(cronometro.transcurrido, const Duration(seconds: 40));
      expect(cronometro.marcha, MarchaCronometro.enCurso);
    });

    test('alternarPausa va y vuelve entre pausa y marcha', () {
      cronometro.iniciar();

      cronometro.alternarPausa();
      expect(cronometro.marcha, MarchaCronometro.pausado);

      cronometro.alternarPausa();
      expect(cronometro.marcha, MarchaCronometro.enCurso);
    });

    test('autoPausar congela el tiempo sin perderlo', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(seconds: 40));

      cronometro.autoPausar();
      reloj.avanzar(const Duration(minutes: 3));

      expect(cronometro.transcurrido, const Duration(seconds: 40));
      expect(cronometro.marcha, MarchaCronometro.autoPausado);
    });

    test('autoReanudar sigue desde donde iba', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(seconds: 40));
      cronometro.autoPausar();
      reloj.avanzar(const Duration(minutes: 3));

      cronometro.autoReanudar();
      reloj.avanzar(const Duration(seconds: 20));

      expect(cronometro.transcurrido, const Duration(seconds: 60));
      expect(cronometro.marcha, MarchaCronometro.enCurso);
    });

    test('una pausa manual no la levanta la auto-reanudación', () {
      cronometro.iniciar();
      cronometro.pausar();

      cronometro.autoReanudar();

      expect(cronometro.marcha, MarchaCronometro.pausado);
    });

    test('estando en pausa manual no se auto-pausa', () {
      cronometro.iniciar();
      cronometro.pausar();

      cronometro.autoPausar();

      expect(cronometro.marcha, MarchaCronometro.pausado);
    });

    test('pausar durante una auto-pausa la vuelve manual sin mover el tiempo',
        () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(seconds: 40));
      cronometro.autoPausar();
      reloj.avanzar(const Duration(minutes: 3));

      cronometro.pausar();

      expect(cronometro.marcha, MarchaCronometro.pausado);
      expect(cronometro.transcurrido, const Duration(seconds: 40));
    });

    test('alternarPausa saca de la auto-pausa', () {
      cronometro.iniciar();
      cronometro.autoPausar();

      cronometro.alternarPausa();

      expect(cronometro.marcha, MarchaCronometro.enCurso);
    });

    test('detener conserva el tiempo total de la actividad', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(minutes: 25, seconds: 8));

      cronometro.detener();
      reloj.avanzar(const Duration(minutes: 3));

      expect(cronometro.transcurrido, const Duration(minutes: 25, seconds: 8));
      expect(cronometro.marcha, MarchaCronometro.detenido);
    });

    test('reiniciar vuelve todo a cero', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(minutes: 4));

      cronometro.reiniciar();

      expect(cronometro.transcurrido, Duration.zero);
      expect(cronometro.marcha, MarchaCronometro.detenido);
    });

    test('no pierde tiempo si la app estuvo en segundo plano', () {
      cronometro.iniciar();

      // Sin ningún tick de por medio: el tiempo se calcula contra el
      // reloj del sistema, no sumando ticks.
      reloj.avanzar(const Duration(minutes: 7, seconds: 3));

      expect(cronometro.estado.tiempoFormateado, '00:07:03');
    });

    test('un reloj que retrocede no resta tiempo ya contado', () {
      cronometro.iniciar();
      reloj.avanzar(const Duration(minutes: 2));
      cronometro.pausar();
      cronometro.reanudar();

      reloj.avanzar(const Duration(minutes: -10));

      expect(cronometro.transcurrido, const Duration(minutes: 2));
    });
  });

  group('formatearTiempoEntrenamiento', () {
    test('usa siempre HH:MM:SS con dos dígitos', () {
      expect(formatearTiempoEntrenamiento(Duration.zero), '00:00:00');
      expect(formatearTiempoEntrenamiento(const Duration(seconds: 9)),
          '00:00:09');
      expect(formatearTiempoEntrenamiento(const Duration(seconds: 61)),
          '00:01:01');
      expect(
        formatearTiempoEntrenamiento(
          const Duration(hours: 1, minutes: 1, seconds: 1),
        ),
        '01:01:01',
      );
    });

    test('trunca los milisegundos al segundo en curso', () {
      expect(
        formatearTiempoEntrenamiento(const Duration(milliseconds: 1999)),
        '00:00:01',
      );
    });

    test('las horas crecen más allá de 99', () {
      expect(formatearTiempoEntrenamiento(const Duration(hours: 100)),
          '100:00:00');
    });

    test('una duración negativa se muestra como cero', () {
      expect(formatearTiempoEntrenamiento(const Duration(seconds: -5)),
          '00:00:00');
    });
  });

  group('EstadoCronometro', () {
    test('el estado inicial arranca en cero y detenido', () {
      const estado = EstadoCronometro.inicial();

      expect(estado.transcurrido, Duration.zero);
      expect(estado.marcha, MarchaCronometro.detenido);
      expect(estado.tiempoFormateado, '00:00:00');
      expect(estado.estaEnCurso, isFalse);
      expect(estado.estaPausado, isFalse);
    });

    test('dos estados con los mismos datos son iguales', () {
      const uno = EstadoCronometro(
        transcurrido: Duration(seconds: 5),
        marcha: MarchaCronometro.enCurso,
      );
      const otro = EstadoCronometro(
        transcurrido: Duration(seconds: 5),
        marcha: MarchaCronometro.enCurso,
      );

      expect(uno, otro);
      expect(uno.hashCode, otro.hashCode);
    });
  });
}
