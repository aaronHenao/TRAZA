import 'package:flutter_test/flutter_test.dart';
import 'package:traza/screens/auth/conocer_traza_screen.dart';
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

    test('la presentación de la app se puede ver sin cuenta', () {
      // Criterio 1 de SCRUM-277: su razón de ser es que alguien decida si se
      // registra, así que no puede exigir estar registrado.
      expect(rutasSinSesion, contains(ConocerTrazaScreen.ruta));
      expect(
        redireccionPorSesion(haySesion: false, ruta: ConocerTrazaScreen.ruta),
        isNull,
      );
    });

    test('con sesión también se puede abrir', () {
      // Se entra igual desde el perfil: no se redirige a Inicio como pasa
      // con el login y el registro.
      expect(
        redireccionPorSesion(haySesion: true, ruta: ConocerTrazaScreen.ruta),
        isNull,
      );
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

    test(
      'SCRUM-81: sin terminar Perfil y Permisos, el login lleva a Perfil',
      () {
        for (final ruta in ['/login', '/registro']) {
          expect(
            redireccionPorSesion(
              haySesion: true,
              ruta: ruta,
              requiereOnboarding: true,
            ),
            '/perfil',
            reason: ruta,
          );
        }
      },
    );

    // Si marcar el onboarding falla, "Continuar" igual debe llegar a Inicio.
    test('no encierra en Perfil a quien ya está en la app', () {
      expect(
        redireccionPorSesion(
          haySesion: true,
          ruta: '/inicio',
          requiereOnboarding: true,
        ),
        isNull,
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
