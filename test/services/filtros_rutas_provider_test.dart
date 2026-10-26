import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/dificultad.dart';
import 'package:traza/models/filtros_rutas.dart';
import 'package:traza/models/rango_distancia.dart';
import 'package:traza/services/filtros_rutas_provider.dart';

/// Pruebas de lo elegido para filtrar en Explorar rutas (SCRUM-273 a
/// SCRUM-275).
void main() {
  late ProviderContainer contenedor;

  setUp(() {
    contenedor = ProviderContainer();
    // Como la pantalla: mientras alguien escucha, lo elegido no se borra.
    contenedor.listen(filtrosRutasProvider, (_, _) {});
  });

  tearDown(() => contenedor.dispose());

  test('empieza sin nada elegido', () {
    expect(contenedor.read(filtrosRutasProvider), const FiltrosRutas());
  });

  test('junta la dificultad y la distancia elegidas', () {
    contenedor.read(dificultadRutasProvider.notifier).state =
        Dificultad.moderada;
    contenedor.read(rangoDistanciaProvider.notifier).state =
        RangoDistancia.de10a20;

    expect(
      contenedor.read(filtrosRutasProvider),
      const FiltrosRutas(
        dificultad: Dificultad.moderada,
        distancia: RangoDistancia.de10a20,
      ),
    );
  });

  test('quitar uno deja el otro', () {
    contenedor.read(dificultadRutasProvider.notifier).state = Dificultad.facil;
    contenedor.read(rangoDistanciaProvider.notifier).state =
        RangoDistancia.menosDe5;

    contenedor.read(rangoDistanciaProvider.notifier).state = null;

    expect(
      contenedor.read(filtrosRutasProvider),
      const FiltrosRutas(dificultad: Dificultad.facil),
    );
  });
}
