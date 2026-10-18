import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/notificacion.dart';
import 'package:traza/screens/notificaciones/notificaciones_screen.dart';
import 'package:traza/services/cambios_notificaciones.dart';
import 'package:traza/services/foro_service.dart' show usuarioActualProvider;
import 'package:traza/services/notificaciones_service.dart';
import 'package:traza/services/reloj_provider.dart';

import '../utiles/fuente_cambios_notificaciones_falsa.dart';
import '../utiles/notificaciones_falso.dart';

/// El aviso al autor cuando le rechazan una ruta (SCRUM-331, criterios 3 y 5
/// de SCRUM-321).
///
/// La notificación la crea la base (`avisar_ruta_rechazada`, 0037): aquí se
/// comprueba que la app la entiende y la muestra con su motivo.
void main() {
  // Lo que escribe `avisar_ruta_rechazada` en cada etapa.
  const delAdministrador =
      '«Vuelta al estadio» fue rechazada por el administrador. '
      'Motivo: Cruza una autopista';
  const delExperto =
      '«Loma de los Balsos» fue rechazada por un Runner Experto. '
      'Motivo: No es apta para principiantes';

  test('la fila que crea la base se lee como un rechazo de ruta', () {
    final aviso = Notificacion.desdeSupabase({
      'id': 'aviso-1',
      'usuario_id': 'autor-1',
      'tipo': 'ruta_rechazada',
      'titulo': 'Tu ruta no fue publicada',
      'mensaje': delAdministrador,
      'entidad_id': 'ruta-1',
      'leida_en': null,
      'fecha_creacion': '2026-10-18T12:00:00Z',
    });

    expect(aviso, isNotNull);
    expect(aviso!.tipo, TipoNotificacion.rutaRechazada);
    expect(aviso.entidadId, 'ruta-1');
  });

  testWidgets('el autor ve que se rechazo, quien lo hizo y por que', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: NotificacionesScreen.ruta,
      routes: [
        GoRoute(
          path: NotificacionesScreen.ruta,
          builder: (_, _) => const NotificacionesScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificacionesRepositoryProvider.overrideWithValue(
            NotificacionesFalso(
              notificaciones: [
                notificacionDePrueba(
                  tipo: TipoNotificacion.rutaRechazada,
                  titulo: 'Tu ruta no fue publicada',
                  mensaje: delAdministrador,
                  fechaCreacion: DateTime(2026, 10, 18, 11),
                ),
                notificacionDePrueba(
                  id: 'aviso-2',
                  tipo: TipoNotificacion.rutaRechazada,
                  titulo: 'Tu ruta no fue publicada',
                  mensaje: delExperto,
                  fechaCreacion: DateTime(2026, 10, 18, 10),
                ),
              ],
            ),
          ),
          fuenteCambiosNotificacionesProvider.overrideWithValue(
            FuenteCambiosNotificacionesFalsa(),
          ),
          usuarioActualProvider.overrideWithValue(() => 'autor-1'),
          relojProvider.overrideWithValue(() => DateTime(2026, 10, 18, 12)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu ruta no fue publicada'), findsNWidgets(2));
    expect(find.text(delAdministrador), findsOneWidget);
    expect(find.text(delExperto), findsOneWidget);
    expect(find.byIcon(TipoNotificacion.rutaRechazada.icono), findsNWidgets(2));
  });

  test('el mensaje mas largo posible cabe en la notificacion', () {
    // Nombre de 120 (0029) y motivo de 300 (0036) en la plantilla de 0037.
    final mensaje =
        '«${'n' * 120}» fue rechazada por un Runner Experto. '
        'Motivo: ${'m' * 300}';

    expect(mensaje.length, lessThanOrEqualTo(500));
  });
}
