import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/screens/foro/detalle_publicacion_screen.dart';
import 'package:traza/screens/foro/nueva_publicacion_screen.dart';
import 'package:traza/services/entrenamiento_provider.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/retos_provider.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/widgets/traza_toast.dart';

/// Los avisos que más salen, y los que tenían más texto antes de la feria.
const _avisos = [
  PublicacionRuta.enRevision,
  PublicacionRuta.sinDatosParaClasificar,
  PublicacionRuta.datosRechazados,
  ClasificacionRuta.clasificada,
  ClasificacionRuta.sinPermiso,
  ConfirmacionPublicacionRuta.publicada,
  ConfirmacionPublicacionRuta.yaCambio,
  NuevaPublicacionScreen.enRevision,
  NuevaPublicacionScreen.edicionEnRevision,
  DetallePublicacionScreen.comentarioEnRevision,
  CreacionPublicacion.datosRechazados,
  ComentarioPublicacion.enRevision,
  ComentarioPublicacion.noDisponible,
  EdicionComentario.yaEnRevision,
  ReportePublicacion.recibido,
  ReportePublicacion.duplicado,
  InicioEntrenamiento.noSePudo,
  InicioEntrenamiento.ubicacionApagada,
  RetiradaReto.corredoresEnJuego,
];

void main() {
  group('cuánto dura el aviso', () {
    test('uno corto se queda lo mínimo, para alcanzar a notarlo', () {
      expect(duracionDeToast('Comentario actualizado'), duracionMinimaToast);
    });

    test('nunca dura menos de 6 segundos', () {
      expect(duracionMinimaToast, const Duration(seconds: 6));
    });

    test('el aviso más largo de las rutas da tiempo de leerlo sin apuro', () {
      expect(
        duracionDeToast(PublicacionRuta.enRevision),
        greaterThan(const Duration(milliseconds: 6500)),
      );
    });

    test('uno más largo se queda más tiempo', () {
      expect(duracionDeToast('a' * 60), greaterThan(duracionDeToast('a' * 45)));
    });

    test('nunca pasa del máximo, por largo que sea', () {
      expect(duracionDeToast('a' * 500), duracionMaximaToast);
    });

    test('los avisos del foro y de las rutas se alcanzan a leer sin llegar '
        'al tope', () {
      for (final mensaje in _avisos) {
        expect(
          duracionDeToast(mensaje),
          lessThan(duracionMaximaToast),
          reason: mensaje,
        );
      }
    });
  });

  test('ningún aviso pasa de dos renglones (60 caracteres): lo que no cabe '
      'va en la pantalla', () {
    for (final mensaje in _avisos) {
      expect(mensaje.length, lessThanOrEqualTo(60), reason: mensaje);
    }
  });

  Future<void> montar(WidgetTester tester, String mensaje) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => mostrarToast(context, mensaje),
            child: const Text('Avisar'),
          ),
        ),
      ),
    ),
  );

  testWidgets('el aviso sigue en pantalla mientras se lee y después se va', (
    tester,
  ) async {
    const mensaje = ReportePublicacion.recibido;
    await montar(tester, mensaje);

    await tester.tap(find.text('Avisar'));
    await tester.pumpAndSettle();
    // Con los 4 s mínimos de antes ya se habría ido.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text(mensaje), findsOneWidget);

    await tester.pump(duracionDeToast(mensaje));
    await tester.pumpAndSettle();
    expect(find.text(mensaje), findsNothing);
  });

  testWidgets('la X lo cierra antes, para quien ya lo leyó', (tester) async {
    const mensaje = PublicacionRuta.enRevision;
    await montar(tester, mensaje);

    await tester.tap(find.text('Avisar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text(mensaje), findsNothing);
  });
}
