import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/punto_gps.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/services/rutas_service.dart';

import '../utiles/rutas_repository_falso.dart';

/// Lo que le dice publicar al autor según los datos de su ruta (SCRUM-363):
/// con la distancia registrada va a un Runner Experto y queda pendiente de
/// revisión; sin ella no se puede clasificar y queda con la dificultad
/// pendiente.
///
/// Quien decide el estado es la base (`preparar_ruta`, 0045). Aquí se prueba
/// que la app lo lee bien y se lo cuenta al autor.
void main() {
  late RutasRepositorioFalso repositorio;
  late ProviderContainer container;

  setUp(() {
    repositorio = RutasRepositorioFalso();
    container = ProviderContainer(
      overrides: [rutasRepositoryProvider.overrideWithValue(repositorio)],
    );
    addTearDown(container.dispose);
  });

  // ~1,1 km en línea recta, con un punto cada ~11 m. Tiene que ser bastante
  // más largo que los dos radios de privacidad (RNF-04) o no quedaría trazo
  // que publicar.
  final borrador = BorradorRuta(
    entrenamientoId: 'e-123',
    nombre: 'Vuelta al estadio',
    puntos: [
      for (var i = 0; i <= 100; i++)
        PuntoGps(
          latitud: 6.2442 + i / 10000,
          longitud: -75.5812,
          capturadoEn: DateTime(2026, 10, 17, 7).add(Duration(seconds: i * 5)),
        ),
    ],
  );

  test('con la distancia registrada la ruta va a un Runner Experto y queda '
      'pendiente de revision (criterio 1 de SCRUM-363)', () async {
    repositorio.distanciaNueva = 5.23;

    final resultado = await container
        .read(publicacionRutaProvider)
        .publicar(borrador);

    final ruta = (resultado as RutaEnRevision).ruta;
    expect(ruta.estado, EstadoRuta.enRevision);
    expect(ruta.dificultad, isNull);
    // Lo que se le dice al autor nombra el estado.
    expect(PublicacionRuta.enRevision, contains('pendiente de revisión'));
    // Primero el administrador y después el experto (SCRUM-321).
    expect(PublicacionRuta.enRevision, contains('administrador'));
    expect(PublicacionRuta.enRevision, contains('Runner Experto'));
  });

  test('sin la distancia registrada informa que no puede clasificarse y la '
      'deja con la dificultad pendiente (criterio 3 de SCRUM-363)', () async {
    repositorio.distanciaNueva = null;

    final resultado = await container
        .read(publicacionRutaProvider)
        .publicar(borrador);

    final ruta = (resultado as RutaSinClasificar).ruta;
    expect(ruta.estado, EstadoRuta.datosIncompletos);
    expect(ruta.dificultad, isNull);
    // Quedó registrada: no es un error que haya que reintentar.
    expect(repositorio.creaciones, 1);
    expect(repositorio.rutas.single.estado, EstadoRuta.datosIncompletos);
    expect(
      PublicacionRuta.sinDatosParaClasificar,
      contains('No pudimos clasificar'),
    );
    expect(
      PublicacionRuta.sinDatosParaClasificar,
      contains('dificultad pendiente'),
    );
  });

  test('un borrador sin nombre sigue sin llegar a la base', () async {
    final resultado = await container
        .read(publicacionRutaProvider)
        .publicar(borrador.copyWith(nombre: '  '));

    expect(resultado, isA<RutaConErrores>());
    expect(repositorio.creaciones, 0);
  });
}
