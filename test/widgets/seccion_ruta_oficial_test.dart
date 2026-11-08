import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:traza/models/ruta.dart';
import 'package:traza/models/verificacion_ruta.dart';
import 'package:traza/services/mapa_progresion_provider.dart';
import 'package:traza/services/rutas_oficiales_service.dart';
import 'package:traza/widgets/seccion_ruta_oficial.dart';

import '../utiles/rutas_oficiales_repository_falso.dart';
import '../utiles/rutas_repository_falso.dart';

final _estadio = rutaDePrueba(
  id: 'ruta-estadio',
  nombre: 'Vuelta al estadio',
  estado: EstadoRuta.publicada,
);
final _nutibara = rutaDePrueba(
  id: 'ruta-nutibara',
  nombre: 'Cerro Nutibara',
  estado: EstadoRuta.publicada,
);

const _completada = VerificacionRuta(
  cobertura: 0.95,
  necesaria: 0.9,
  completada: true,
);
const _incompleta = VerificacionRuta(
  cobertura: 0.72,
  necesaria: 0.9,
  completada: false,
);

/// Pruebas de lo que dice el resumen sobre la ruta oficial que se corrió
/// (rutas oficiales, etapa 4).
///
/// Si se completó lo decide la base (`verificar_ruta_completada`): aquí se
/// prueba que la sección pida ese resultado, lo muestre tal cual y, si la
/// ruta quedó completada, haga que el mapa de progresión avance.
void main() {
  late RutasOficialesRepositorioFalso repositorio;

  setUp(() {
    repositorio = RutasOficialesRepositorioFalso(
      oficiales: [_estadio, _nutibara],
    );
  });

  /// Monta la sección del entrenamiento `e-1`, que corrió la Vuelta al
  /// estadio. Con [mapaAbierto], el mapa de progresión está vivo al lado,
  /// como cuando su pestaña ya se abrió antes.
  Future<void> montar(
    WidgetTester tester, {
    bool mapaAbierto = false,
    bool asentar = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rutasOficialesRepositoryProvider.overrideWithValue(repositorio),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  if (mapaAbierto) const _MapaAbierto(),
                  const SeccionRutaOficial(
                    entrenamientoId: 'e-1',
                    nombreRuta: 'Vuelta al estadio',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Mientras comprueba puede haber un indicador animado: no se espera a
    // que la pantalla quede quieta.
    if (asentar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  testWidgets('le pide a la base la verificación de su entrenamiento '
      '(criterio 1)', (tester) async {
    repositorio.verificacion = _incompleta;

    await montar(tester);

    expect(repositorio.verificados, ['e-1']);
    expect(find.byKey(SeccionRutaOficial.clave), findsOneWidget);
  });

  group('si se completó (criterio 2)', () {
    testWidgets('dice "¡Completaste <ruta>!" y cuánto del trazado cubrió', (
      tester,
    ) async {
      repositorio.verificacion = _completada;

      await montar(tester);

      expect(find.text('¡Completaste Vuelta al estadio!'), findsOneWidget);
      expect(find.text('Cubriste el 95 % del trazado.'), findsOneWidget);
      // No se mezcla con el mensaje de la que falta.
      expect(find.textContaining('Necesitas'), findsNothing);
      expect(find.textContaining('% de Vuelta al estadio'), findsNothing);
    });

    testWidgets('justo en el umbral también la da por completada', (
      tester,
    ) async {
      repositorio.verificacion = const VerificacionRuta(
        cobertura: 0.9,
        necesaria: 0.9,
        completada: true,
      );

      await montar(tester);

      expect(find.text('¡Completaste Vuelta al estadio!'), findsOneWidget);
      expect(find.text('Cubriste el 90 % del trazado.'), findsOneWidget);
    });

    testWidgets('el mapa de progresión se vuelve a consultar y avanza', (
      tester,
    ) async {
      repositorio
        ..verificacion = _completada
        ..esperaVerificar = Completer<void>();

      await montar(tester, mapaAbierto: true, asentar: false);

      // El mapa ya se había leído antes de saber el resultado.
      expect(repositorio.consultas, 1);
      expect(repositorio.consultasCompletadas, 1);
      expect(find.text('Completadas en el mapa: 0'), findsOneWidget);

      // Lo que hizo la base al verificar: dejar la ruta en
      // `rutas_completadas`.
      repositorio.completadasPorMi.add('ruta-estadio');
      repositorio.esperaVerificar!.complete();
      await tester.pumpAndSettle();

      // Una sola vez más: no se queda releyendo el mapa en cada dibujo.
      expect(repositorio.consultas, 2);
      expect(repositorio.consultasCompletadas, 2);
      expect(find.text('Completadas en el mapa: 1'), findsOneWidget);
    });
  });

  group('si no se completó (criterio 3)', () {
    testWidgets('dice cuánto cubrió de la ruta y cuánto necesita', (
      tester,
    ) async {
      repositorio.verificacion = _incompleta;

      await montar(tester);

      expect(
        find.text('Cubriste el 72 % de Vuelta al estadio'),
        findsOneWidget,
      );
      expect(find.text('Necesitas el 90 % para completarla.'), findsOneWidget);
      expect(find.textContaining('¡Completaste'), findsNothing);
      expect(find.textContaining('del trazado'), findsNothing);
    });

    testWidgets('redondea hacia abajo: con 0.899 dice 89 %, nunca 90', (
      tester,
    ) async {
      repositorio.verificacion = const VerificacionRuta(
        cobertura: 0.899,
        necesaria: 0.9,
        completada: false,
      );

      await montar(tester);

      expect(
        find.text('Cubriste el 89 % de Vuelta al estadio'),
        findsOneWidget,
      );
      expect(find.text('Cubriste el 90 % de Vuelta al estadio'), findsNothing);
    });

    testWidgets('el umbral es el que manda la base, no uno escrito en la '
        'app', (tester) async {
      repositorio.verificacion = const VerificacionRuta(
        cobertura: 0.72,
        necesaria: 0.85,
        completada: false,
      );

      await montar(tester);

      expect(find.text('Necesitas el 85 % para completarla.'), findsOneWidget);
      expect(find.textContaining('90 %'), findsNothing);
    });

    testWidgets('quien decide si se completó es la base, no el porcentaje', (
      tester,
    ) async {
      // La cobertura pasa el umbral, pero la base dijo que no: la app no
      // recalcula nada por su cuenta.
      repositorio.verificacion = const VerificacionRuta(
        cobertura: 0.95,
        necesaria: 0.9,
        completada: false,
      );

      await montar(tester);

      expect(find.textContaining('¡Completaste'), findsNothing);
      expect(
        find.text('Cubriste el 95 % de Vuelta al estadio'),
        findsOneWidget,
      );
    });

    testWidgets('el mapa de progresión no se vuelve a consultar', (
      tester,
    ) async {
      repositorio.verificacion = _incompleta;

      await montar(tester, mapaAbierto: true);

      expect(repositorio.verificados, ['e-1']);
      expect(repositorio.consultas, 1);
      expect(repositorio.consultasCompletadas, 1);
      expect(find.text('Completadas en el mapa: 0'), findsOneWidget);
    });
  });

  group('mientras comprueba', () {
    testWidgets('dice "Comprobando si completaste la ruta…" y luego el '
        'resultado', (tester) async {
      repositorio
        ..verificacion = _incompleta
        ..esperaVerificar = Completer<void>();

      await montar(tester, asentar: false);

      expect(find.text('Comprobando si completaste la ruta…'), findsOneWidget);
      expect(find.byKey(SeccionRutaOficial.clave), findsOneWidget);
      expect(find.textContaining('Cubriste'), findsNothing);

      repositorio.esperaVerificar!.complete();
      await tester.pumpAndSettle();

      expect(find.text('Comprobando si completaste la ruta…'), findsNothing);
      expect(
        find.text('Cubriste el 72 % de Vuelta al estadio'),
        findsOneWidget,
      );
    });
  });

  group('errores: siempre legibles, nunca crudos', () {
    testWidgets('si la base no pudo validar el recorrido, lo dice sin ofrecer '
        'reintentar', (tester) async {
      repositorio.errorAlVerificar = const RecorridoNoValidoException();

      await montar(tester);

      expect(find.text('No pudimos validar este recorrido'), findsOneWidget);
      // Reintentar no cambia un recorrido que la base ya rechazó.
      expect(find.text('Reintentar'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('si la ruta ya no es oficial, dice que ya no es parte del '
        'mapa', (tester) async {
      repositorio.errorAlVerificar = const RutaNoOficialException();

      await montar(tester);

      expect(find.text('Esta ruta ya no es parte del mapa'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    for (final (causa, error, crudo) in [
      (
        'la base lo niega',
        const PostgrestException(
          message: 'permission denied for function verificar_ruta_completada',
          code: '42501',
        ),
        'permission denied',
      ),
      (
        'se cayó la red',
        StateError('Supabase no disponible'),
        'Supabase no disponible',
      ),
    ]) {
      testWidgets('si $causa, dice que no pudo comprobarla y ofrece '
          'reintentar, sin el mensaje crudo', (tester) async {
        repositorio.errorAlVerificar = error;

        await montar(tester);

        expect(find.text('No pudimos comprobar la ruta'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.textContaining(crudo), findsNothing);
        expect(find.textContaining('42501'), findsNothing);
        expect(find.textContaining('¡Completaste'), findsNothing);
      });
    }

    testWidgets('"Reintentar" vuelve a consultar y muestra el resultado', (
      tester,
    ) async {
      repositorio
        ..verificacion = _incompleta
        ..errorAlVerificar = StateError('Supabase no disponible');

      await montar(tester);
      expect(find.text('No pudimos comprobar la ruta'), findsOneWidget);

      // Vuelve la conexión, pero tarda: mientras, dice que está comprobando
      // y no deja el error a la vista.
      repositorio
        ..errorAlVerificar = null
        ..esperaVerificar = Completer<void>();
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(find.text('Comprobando si completaste la ruta…'), findsOneWidget);
      expect(find.text('No pudimos comprobar la ruta'), findsNothing);

      repositorio.esperaVerificar!.complete();
      await tester.pumpAndSettle();

      expect(repositorio.verificados, ['e-1', 'e-1']);
      expect(find.text('No pudimos comprobar la ruta'), findsNothing);
      expect(
        find.text('Cubriste el 72 % de Vuelta al estadio'),
        findsOneWidget,
      );
    });
  });

  testWidgets('si la base dice que el entrenamiento no tiene ruta, no inventa '
      'un resultado', (tester) async {
    // `verificar` devuelve null: no hay nada que comparar.
    repositorio.verificacion = null;

    await montar(tester);

    expect(repositorio.verificados, ['e-1']);
    expect(find.textContaining('Completaste'), findsNothing);
    expect(find.textContaining('Cubriste'), findsNothing);
    expect(find.textContaining('Comprobando'), findsNothing);
    expect(find.textContaining('No pudimos'), findsNothing);
    // Ni siquiera la caja vacía.
    expect(find.byKey(SeccionRutaOficial.clave), findsNothing);
  });
}

/// El mapa de progresión ya abierto en su pestaña: lo mantiene vivo y
/// muestra cuántas rutas lleva el corredor.
class _MapaAbierto extends ConsumerWidget {
  const _MapaAbierto();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapa = ref.watch(mapaProgresionProvider).valueOrNull;
    return Text('Completadas en el mapa: ${mapa?.totalCompletadas ?? '-'}');
  }
}
