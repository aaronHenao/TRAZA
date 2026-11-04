import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/services/foro_provider.dart';
import 'package:traza/services/rutas_provider.dart';
import 'package:traza/widgets/traza_toast.dart';

void main() {
  group('cuánto dura el aviso', () {
    test('uno corto se queda lo mínimo, para alcanzar a notarlo', () {
      expect(duracionDeToast('Comentario actualizado'), duracionMinimaToast);
    });

    test('uno más largo se queda más tiempo', () {
      expect(
        duracionDeToast(PublicacionRuta.enRevision),
        greaterThan(duracionDeToast(ComentarioPublicacion.enRevision)),
      );
    });

    test('nunca pasa del máximo, por largo que sea', () {
      expect(duracionDeToast('a' * 500), duracionMaximaToast);
    });

    test('los avisos del foro y de las rutas se alcanzan a leer sin llegar '
        'al tope', () {
      for (final mensaje in [
        PublicacionRuta.enRevision,
        PublicacionRuta.sinDatosParaClasificar,
        ComentarioPublicacion.enRevision,
        ReportePublicacion.recibido,
      ]) {
        expect(
          duracionDeToast(mensaje),
          lessThan(duracionMaximaToast),
          reason: mensaje,
        );
      }
    });
  });

  testWidgets('el aviso sigue en pantalla mientras se lee y después se va', (
    tester,
  ) async {
    const mensaje = PublicacionRuta.enRevision;
    await tester.pumpWidget(
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

    await tester.tap(find.text('Avisar'));
    await tester.pumpAndSettle();
    // Con el tiempo fijo de antes ya se habría ido.
    await tester.pump(const Duration(milliseconds: 2400));
    expect(find.text(mensaje), findsOneWidget);

    await tester.pump(duracionDeToast(mensaje));
    await tester.pumpAndSettle();
    expect(find.text(mensaje), findsNothing);
  });
}
