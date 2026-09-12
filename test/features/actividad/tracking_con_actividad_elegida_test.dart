import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/features/actividad/data/tipos_actividad_repository.dart';
import 'package:traza/features/actividad/domain/tipo_actividad.dart';
import 'package:traza/features/actividad/presentation/actividad_providers.dart';
import 'package:traza/features/actividad/presentation/tracking_con_actividad_elegida.dart';
import 'package:traza/screens/tracking/tracking_screen.dart';
import 'package:traza/services/cronometro_provider.dart';
import 'package:traza/services/mapa_provider.dart';
import 'package:traza/services/recorrido_provider.dart';
import 'package:traza/services/ubicacion_provider.dart';

import '../../utiles/fuente_ubicacion_falsa.dart';
import '../../utiles/proveedor_tiles_falso.dart';
import '../../utiles/reloj_falso.dart';
import '../../utiles/repositorio_puntos_gps_falso.dart';

/// Pruebas de la parte B de SCRUM-93 y de la verificación que SCRUM-95 dejó
/// pendiente: la pantalla del entrenamiento en curso de Aaron recibe la
/// actividad que el usuario eligió en los chips del inicio.
///
/// La pantalla se monta con los mismos falsos que usan las pruebas de Aaron
/// (`test/screens/tracking_screen_test.dart`), para no tocar el GPS real.
void main() {
  testWidgets('con una actividad elegida, la pantalla del entrenamiento la '
      'recibe y la muestra', (tester) async {
    final container = await _montar(tester, catalogo: _catalogo, elegir: 'Trote');

    final pantalla = tester.widget<TrackingScreen>(find.byType(TrackingScreen));
    expect(pantalla.nombreActividad, 'Trote');
    expect(find.text('Trote'), findsWidgets);

    _detenerCronometro(container);
  });

  testWidgets('sin sesión, aunque se elija otra, abre con la actividad por '
      'defecto de la pantalla', (tester) async {
    // Sin sesión el catálogo es el local, sin ids: no hay configuración de
    // inicio y la pantalla usa su valor por defecto ("Correr").
    final container = await _montar(
      tester,
      catalogo: TipoActividad.catalogoLocal,
      elegir: 'Trote',
    );

    final pantalla = tester.widget<TrackingScreen>(find.byType(TrackingScreen));
    expect(pantalla.nombreActividad, 'Correr');

    _detenerCronometro(container);
  });
}

const _catalogo = [
  TipoActividad(id: 'id-correr', nombre: 'Correr'),
  TipoActividad(id: 'id-trote', nombre: 'Trote'),
  TipoActividad(id: 'id-caminar', nombre: 'Caminar'),
];

class _CatalogoFalso implements TiposActividadRepository {
  const _CatalogoFalso(this.tipos);

  final List<TipoActividad> tipos;

  @override
  Future<List<TipoActividad>> cargar() async => tipos;
}

/// Hace lo mismo que los chips del inicio (carga el catálogo y elige
/// [elegir]) y después abre la pantalla del entrenamiento.
Future<ProviderContainer> _montar(
  WidgetTester tester, {
  required List<TipoActividad> catalogo,
  required String elegir,
}) async {
  final fuente = FuenteUbicacionFalsa();
  addTearDown(fuente.cerrar);

  final container = ProviderContainer(
    overrides: [
      relojProvider.overrideWithValue(RelojFalso().call),
      fuenteUbicacionProvider.overrideWithValue(fuente),
      proveedorTilesProvider.overrideWithValue(ProveedorTilesFalso()),
      repositorioPuntosGpsProvider.overrideWithValue(
        RepositorioPuntosGpsFalso(),
      ),
      entrenamientoActualProvider.overrideWithValue('e-123'),
      tiposActividadRepositoryProvider.overrideWithValue(
        _CatalogoFalso(catalogo),
      ),
    ],
  );
  addTearDown(container.dispose);

  final tipos = await container.read(tiposActividadProvider.future);
  container
      .read(actividadSeleccionadaProvider.notifier)
      .seleccionar(tipos.firstWhere((tipo) => tipo.nombre == elegir));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: TrackingConActividadElegida()),
    ),
  );
  // La pantalla inicia el cronómetro en el primer frame.
  await tester.pump();

  return container;
}

/// Igual que en las pruebas de Aaron: se detiene el cronómetro antes de
/// terminar para no dejar su temporizador vivo.
void _detenerCronometro(ProviderContainer container) =>
    container.read(cronometroProvider.notifier).detener();
