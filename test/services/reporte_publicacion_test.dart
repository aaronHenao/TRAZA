import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/reporte_foro.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/foro_service.dart';

import '../utiles/foro_repository_falso.dart';

/// Reportar una publicación del foro (SCRUM-369): qué le responde la app al
/// corredor en cada caso y la bandeja del administrador.
void main() {
  late ForoRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    // `publicacionDePrueba(id: 'pub-1')` la escribió 'autor-pub-1'; reporta
    // `ForoRepositorioFalso.usuario`.
    repositorio = ForoRepositorioFalso(
      publicaciones: [publicacionDePrueba(id: 'pub-1')],
    );
    container = ProviderContainer(
      overrides: [
        foroRepositoryProvider.overrideWithValue(repositorio),
        usuarioActualProvider.overrideWithValue(
          () => ForoRepositorioFalso.usuario,
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<ResultadoReporte> reportar(MotivoReporte motivo, {String? detalle}) =>
      container
          .read(reporteForoProvider)
          .reportar('pub-1', motivo, detalle: detalle);

  /// Los reportes que el usuario de la sesión dejó sobre 'pub-1'.
  Iterable<ReporteForo> delUsuario() => repositorio.reportesGuardados.where(
    (r) =>
        r.publicacionId == 'pub-1' &&
        repositorio.reportanteDe[r.id] == ForoRepositorioFalso.usuario,
  );

  test('registra el reporte con su motivo y confirma que se recibió '
      '(criterio 1 de SCRUM-369)', () async {
    final resultado = await reportar(
      MotivoReporte.acoso,
      detalle: 'Insulta a otro corredor',
    );

    expect(resultado, isA<ReporteRecibido>());
    final reporte = delUsuario().single;
    expect(reporte.motivo, MotivoReporte.acoso);
    expect(reporte.detalle, 'Insulta a otro corredor');
  });

  test('la confirmación le dice que el autor no sabrá quién lo envió '
      '(criterio 2 de SCRUM-369)', () {
    expect(
      ReportePublicacion.recibido,
      'Recibimos tu reporte. El autor no sabrá quién lo envió.',
    );
  });

  test('un motivo que no es "Otro" no exige detalle', () async {
    expect(await reportar(MotivoReporte.spam), isA<ReporteRecibido>());
    expect(delUsuario().single.motivo, MotivoReporte.spam);
  });

  group('reporte duplicado (criterio 3 de SCRUM-369)', () {
    test('si ya la reportó, no registra un segundo reporte y dice que está '
        'en revisión', () async {
      await reportar(MotivoReporte.acoso);

      final otra = await reportar(MotivoReporte.spam);

      expect(otra, isA<ReporteDuplicado>());
      expect(delUsuario(), hasLength(1));
      expect(delUsuario().single.motivo, MotivoReporte.acoso);
      expect(
        ReportePublicacion.duplicado,
        'Ya reportaste esta publicación. Está en revisión.',
      );
    });

    test('lo que reportaron otros no le cuenta como suyo', () async {
      repositorio.reportesGuardados.add(
        reporteDePrueba(id: 'rep-otro', publicacionId: 'pub-1'),
      );

      expect(await reportar(MotivoReporte.acoso), isA<ReporteRecibido>());
      expect(delUsuario(), hasLength(1));
    });
  });

  group('con el motivo "Otro"', () {
    for (final (descripcion, detalle) in [
      ('sin detalle', null),
      ('con solo espacios', '   '),
    ]) {
      test(
        '$descripcion pide contar por qué y no llega al repositorio',
        () async {
          final resultado = await reportar(
            MotivoReporte.otro,
            detalle: detalle,
          );

          expect(resultado, isA<ReporteSinDetalle>());
          expect(repositorio.reporteRecibido, isNull);
          expect(
            ReportePublicacion.sinDetalle,
            'Cuéntanos por qué la reportas.',
          );
        },
      );
    }

    test('con detalle se registra', () async {
      final resultado = await reportar(
        MotivoReporte.otro,
        detalle: 'Publica el teléfono de otra corredora',
      );

      expect(resultado, isA<ReporteRecibido>());
      expect(delUsuario().single.motivo, MotivoReporte.otro);
    });
  });

  test('si la publicación ya no está publicada, lo dice', () async {
    repositorio.rechazar('pub-1');

    final resultado = await reportar(MotivoReporte.spam);

    expect(resultado, isA<ReporteNoDisponible>());
    expect(repositorio.reportesGuardados, isEmpty);
  });

  test('lo propio tampoco se puede reportar aunque se intente: la base tiene '
      'la última palabra', () async {
    repositorio.publicaciones
      ..clear()
      ..add(
        publicacionDePrueba(id: 'pub-1', autorId: ForoRepositorioFalso.usuario),
      );

    expect(await reportar(MotivoReporte.spam), isA<ReporteNoDisponible>());
    expect(repositorio.reportesGuardados, isEmpty);
  });

  test('un fallo de red no se confunde con un duplicado', () async {
    repositorio.errorAlReportar = Exception('sin red');

    final resultado = await reportar(MotivoReporte.spam);

    expect(
      (resultado as ReporteNoGuardado).mensaje,
      ReportePublicacion.noSePudo,
    );
  });

  test('sin sesión pide iniciarla, como el resto del foro', () async {
    repositorio.errorAlReportar = const SesionRequeridaParaForoException();

    final resultado = await reportar(MotivoReporte.spam);

    expect(
      (resultado as ReporteNoGuardado).mensaje,
      ReportePublicacion.sinSesion,
    );
  });

  test('sin sesión no se registra', () async {
    repositorio.errorAlReportar = const SesionRequeridaParaForoException();

    expect(await reportar(MotivoReporte.spam), isA<ReporteNoGuardado>());
    expect(repositorio.reportesGuardados, isEmpty);
  });

  group('bandeja del administrador (criterio 1 de SCRUM-369)', () {
    test('tras registrar el reporte, la bandeja se vuelve a consultar y lo '
        'trae', () async {
      container.listen(publicacionesReportadasProvider, (_, _) {});
      expect(await container.read(reportesForoProvider.future), isEmpty);
      final antes = repositorio.consultasReportes;

      await reportar(MotivoReporte.violencia);

      final despues = await container.read(reportesForoProvider.future);
      expect(repositorio.consultasReportes, greaterThan(antes));
      expect(despues.single.publicacionId, 'pub-1');
      expect(despues.single.motivo, MotivoReporte.violencia);
    });

    test('agrupa los reportes por publicación', () async {
      repositorio.reportesGuardados.addAll([
        reporteDePrueba(
          id: 'r1',
          publicacionId: 'pub-1',
          fecha: DateTime(2026, 10, 16, 10),
        ),
        reporteDePrueba(
          id: 'r2',
          publicacionId: 'pub-1',
          motivo: MotivoReporte.spam,
          fecha: DateTime(2026, 10, 16, 9),
        ),
        reporteDePrueba(
          id: 'r3',
          publicacionId: 'pub-2',
          fecha: DateTime(2026, 10, 16, 8),
        ),
      ]);
      container.listen(publicacionesReportadasProvider, (_, _) {});

      await container.read(reportesForoProvider.future);
      final bandeja = container.read(publicacionesReportadasProvider).value!;

      expect(bandeja.map((p) => p.publicacionId), ['pub-1', 'pub-2']);
      expect(bandeja.first.cuantos, 2);
      expect(bandeja.last.cuantos, 1);
    });
  });
}
