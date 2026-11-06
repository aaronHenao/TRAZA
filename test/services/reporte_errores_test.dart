// Reporte de errores no atrapados a Crashlytics sin datos personales
// (Crashlytics). Los mensajes de Supabase o del GPS pueden traer nombres,
// correos o coordenadas, así que solo viaja el TIPO del error y su pila.
//
// Se usa `test()` y no `testWidgets()`: el binding de pruebas verifica al
// final de cada testWidgets que FlutterError.onError no haya cambiado, y
// capturarErrores lo cambia a propósito.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/services/reporte_errores.dart';

/// Un reporte tal como le llega al destino (en producción, Crashlytics).
typedef _Reporte = ({Object error, StackTrace pila, bool fatal});

/// Datos personales falsos que no pueden salir del teléfono.
const _correo = 'prueba@traza.co';
const _latitud = '6.2442';
const _longitud = '-75.5812';
const _nombre = 'Emmanuel';

/// Error cuyo mensaje trae correo y coordenadas, como los de Supabase o GPS.
StateError _errorConDatosPersonales() =>
    StateError('Falló para $_correo en $_latitud,$_longitud');

/// Afirma que [error] no deja ver ningún dato personal al convertirlo a texto.
void _expectSinDatosPersonales(Object error) {
  final texto = error.toString();
  for (final dato in [_correo, _latitud, _longitud, _nombre]) {
    expect(texto, isNot(contains(dato)), reason: 'se filtró "$dato"');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_Reporte> reportes;
  late List<FlutterErrorDetails> presentados;

  /// Doble del destino: solo anota lo que recibe.
  void reportar(Object error, StackTrace pila, {required bool fatal}) {
    reportes.add((error: error, pila: pila, fatal: fatal));
  }

  setUp(() {
    reportes = [];
    presentados = [];

    // Se guardan los handlers globales para que esta prueba no contamine a
    // las demás del mismo proceso.
    final onErrorFlutter = FlutterError.onError;
    final presentErrorOriginal = FlutterError.presentError;
    final onErrorPlataforma = PlatformDispatcher.instance.onError;
    addTearDown(() {
      FlutterError.onError = onErrorFlutter;
      FlutterError.presentError = presentErrorOriginal;
      PlatformDispatcher.instance.onError = onErrorPlataforma;
    });

    // En vez de imprimir en consola, anota: así se comprueba que se sigue
    // llamando y la salida de la prueba no se llena de datos falsos.
    FlutterError.presentError = presentados.add;

    final ReportarError destino = reportar;
    capturarErrores(destino);
  });

  group('errores de Flutter no atrapados (FlutterError.onError)', () {
    test('se reportan como fatales con su tipo y la misma pila, sin el mensaje '
        'ni la descripción de widgets', () {
      final pila = StackTrace.current;
      final detalles = FlutterErrorDetails(
        exception: _errorConDatosPersonales(),
        stack: pila,
        library: 'widgets library',
        context: ErrorDescription('al construir el perfil de $_correo'),
        informationCollector: () => [
          ErrorDescription('El widget culpable fue: Text("$_nombre")'),
        ],
      );

      FlutterError.onError!(detalles);

      expect(reportes, hasLength(1));
      final reporte = reportes.single;
      expect(reporte.error, isA<String>());
      expect(reporte.error, 'StateError');
      _expectSinDatosPersonales(reporte.error);
      expect(reporte.pila, same(pila));
      expect(reporte.fatal, isTrue);
    });

    test('sin pila en los detalles se reporta con StackTrace.empty', () {
      FlutterError.onError!(
        FlutterErrorDetails(exception: _errorConDatosPersonales()),
      );

      expect(reportes, hasLength(1));
      expect(reportes.single.pila, same(StackTrace.empty));
      expect(reportes.single.fatal, isTrue);
    });

    test('se siguen mostrando en consola con FlutterError.presentError', () {
      // Sin esto, en debug el desarrollador dejaría de ver el error.
      final detalles = FlutterErrorDetails(
        exception: _errorConDatosPersonales(),
        stack: StackTrace.current,
      );

      FlutterError.onError!(detalles);

      expect(presentados, hasLength(1));
      expect(presentados.single, same(detalles));
    });
  });

  group('errores asíncronos no atrapados (PlatformDispatcher.onError)', () {
    test(
      'se reportan como fatales con su tipo y la misma pila, sin el mensaje',
      () {
        final pila = StackTrace.current;

        PlatformDispatcher.instance.onError!(_errorConDatosPersonales(), pila);

        expect(reportes, hasLength(1));
        final reporte = reportes.single;
        expect(reporte.error, isA<String>());
        expect(reporte.error, 'StateError');
        _expectSinDatosPersonales(reporte.error);
        expect(reporte.pila, same(pila));
        expect(reporte.fatal, isTrue);
      },
    );

    test('el handler devuelve true: el error queda atendido', () {
      // Si devolviera false, el motor lo trataría como no manejado y lo
      // volvería a imprimir con el mensaje completo.
      final atendido = PlatformDispatcher.instance.onError!(
        _errorConDatosPersonales(),
        StackTrace.current,
      );

      expect(atendido, isTrue);
    });

    test('si lo lanzado es un String con datos personales se reporta solo '
        '"String"', () {
      // `throw 'texto'` es válido en Dart: el "error" es el propio mensaje.
      PlatformDispatcher.instance.onError!(
        'No se pudo guardar la ruta de $_correo en $_latitud,$_longitud',
        StackTrace.current,
      );

      expect(reportes, hasLength(1));
      expect(reportes.single.error, 'String');
      _expectSinDatosPersonales(reportes.single.error);
    });
  });
}
