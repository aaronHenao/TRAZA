import 'package:flutter_test/flutter_test.dart';
import 'package:traza/screens/auth/rutas_auth.dart';

void main() {
  group('Sin sesión', () {
    test('las pantallas de la app llevan al login', () {
      for (final ruta in ['/inicio', '/perfil', '/tracking', '/resumen/1']) {
        expect(
          redireccionPorSesion(haySesion: false, ruta: ruta),
          '/login',
          reason: ruta,
        );
      }
    });

    test('las pantallas de auth se pueden abrir', () {
      for (final ruta in rutasSinSesion) {
        expect(
          redireccionPorSesion(haySesion: false, ruta: ruta),
          isNull,
          reason: ruta,
        );
      }
    });
  });

  group('Con sesión guardada', () {
    test('abrir el login o el registro lleva directo a Inicio', () {
      expect(redireccionPorSesion(haySesion: true, ruta: '/login'), '/inicio');
      expect(
        redireccionPorSesion(haySesion: true, ruta: '/registro'),
        '/inicio',
      );
    });

    test('las pantallas de la app se abren normal', () {
      expect(redireccionPorSesion(haySesion: true, ruta: '/perfil'), isNull);
    });

    // Verificar el código abre una sesión temporal: no debe sacarla del flujo.
    test('la recuperación de contraseña sigue disponible', () {
      expect(
        redireccionPorSesion(haySesion: true, ruta: '/restablecer'),
        isNull,
      );
    });
  });
}
