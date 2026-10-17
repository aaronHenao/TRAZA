import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/experiencia_ganada.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/models/regla_experiencia.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/widgets/seccion_experiencia.dart';

import '../utiles/experiencia_falsa.dart';
import '../utiles/niveles_falso.dart';

const _bronce = Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100);
const _plata = Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500);
const _oro = Nivel(id: 'n-3', nombre: 'Oro', umbralExperiencia: 1500);

/// Pruebas de la XP en el resumen del entrenamiento (SCRUM-207), con el nivel
/// (SCRUM-198) y el aviso de ascenso (SCRUM-199).
void main() {
  Future<ExperienciaFalsa> montar(
    WidgetTester tester, {
    ExperienciaDeEntrenamiento? xp,
    Object? error,
    int acumulada = 0,
    List<Nivel> niveles = const [],
    bool anunciarAscenso = false,
  }) async {
    final falsa = ExperienciaFalsa(
      acumulada: acumulada,
      porEntrenamiento: {'e-1': ?xp},
    )..error = error;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          experienciaRepositoryProvider.overrideWithValue(falsa),
          nivelesRepositoryProvider.overrideWithValue(
            NivelesFalso(catalogo: niveles),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SeccionExperiencia(
                entrenamientoId: 'e-1',
                anunciarAscenso: anunciarAscenso,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return falsa;
  }

  String total(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(SeccionExperiencia.claveTotal)).data!;

  testWidgets('un entrenamiento libre no da XP', (tester) async {
    await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 0,
        ajuste: AjusteExperiencia.ninguno,
      ),
    );

    expect(find.text('XP obtenida'), findsOneWidget);
    expect(total(tester), '+0 XP');
    // Sin retos no hay desglose.
    expect(find.text('Actividad'), findsNothing);
  });

  testWidgets('siempre explica que la XP sale de los retos', (tester) async {
    await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 0,
        ajuste: AjusteExperiencia.ninguno,
      ),
    );

    expect(
      find.text(
        'Los entrenamientos libres no dan XP: la ganas completando retos. '
        'Tus km cuentan para los retos activos de esta actividad.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('con un reto completado, la XP es la del reto', (tester) async {
    await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 0,
        ajuste: AjusteExperiencia.ninguno,
        retos: [RetoCompletado(nombre: 'Diez km', xp: 400)],
      ),
    );

    expect(total(tester), '+400 XP');
    expect(find.text('Reto «Diez km» completado'), findsOneWidget);
    // La actividad no dio nada: una línea de +0 solo confundiría.
    expect(find.text('Actividad'), findsNothing);
  });

  testWidgets('un entrenamiento anterior conserva su XP de actividad', (
    tester,
  ) async {
    // Finalizado cuando la actividad todavía daba XP.
    await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 30,
        ajuste: AjusteExperiencia.ninguno,
        retos: [RetoCompletado(nombre: 'Diez km', xp: 400)],
      ),
    );

    expect(total(tester), '+430 XP');
    expect(find.text('Actividad'), findsOneWidget);
    expect(find.text('+30 XP'), findsOneWidget);
    expect(find.text('+400 XP'), findsOneWidget);
  });

  testWidgets('explica por qué los km no contaron para los retos', (
    tester,
  ) async {
    const esperados = {
      AjusteExperiencia.velocidadImposible:
          'El promedio superó los 25 km/h, así que este entrenamiento no '
          'cuenta para tus retos.',
      AjusteExperiencia.sinDatos:
          'Sin distancia registrada, este entrenamiento no cuenta para tus '
          'retos.',
    };

    for (final MapEntry(key: ajuste, value: texto) in esperados.entries) {
      await montar(
        tester,
        xp: ExperienciaDeEntrenamiento(xpActividad: 0, ajuste: ajuste),
      );
      expect(find.text(texto), findsOneWidget, reason: ajuste.name);
    }
  });

  testWidgets('el mínimo y el tope de antes no se explican: los km contaron', (
    tester,
  ) async {
    for (final ajuste in [
      AjusteExperiencia.menosDelMinimo,
      AjusteExperiencia.topeDiario,
    ]) {
      await montar(
        tester,
        xp: ExperienciaDeEntrenamiento(xpActividad: 0, ajuste: ajuste),
      );
      expect(
        find.textContaining('no cuenta para tus retos'),
        findsNothing,
        reason: ajuste.name,
      );
      expect(find.textContaining('tope'), findsNothing, reason: ajuste.name);
    }
  });

  testWidgets('un entrenamiento sin XP registrada lo dice', (tester) async {
    // Anterior a la XP, o la XP falló y el cierre se hizo igual.
    await montar(tester);

    expect(
      find.text('Este entrenamiento no tiene XP registrada.'),
      findsOneWidget,
    );
    expect(find.byKey(SeccionExperiencia.claveTotal), findsNothing);
  });

  testWidgets('si no carga, deja reintentar', (tester) async {
    final falsa = await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 25,
        ajuste: AjusteExperiencia.ninguno,
      ),
      error: StateError('Supabase no disponible'),
    );

    expect(find.text('No pudimos cargar tu XP.'), findsOneWidget);

    falsa.error = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(total(tester), '+25 XP');
  });

  group('nivel (SCRUM-198)', () {
    const niveles = [_bronce, _plata, _oro];

    testWidgets('muestra el nivel y cuánto falta para el siguiente', (
      tester,
    ) async {
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 25,
          ajuste: AjusteExperiencia.ninguno,
        ),
        acumulada: 300,
        niveles: niveles,
      );

      expect(find.text('Nivel: Bronce'), findsOneWidget);
      expect(find.text('Te faltan 200 XP para Plata.'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(SeccionExperiencia.claveAvanceNivel),
            )
            .value,
        0.5,
      );
    });

    testWidgets('por debajo del primer umbral todavía no tiene nivel', (
      tester,
    ) async {
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 25,
          ajuste: AjusteExperiencia.ninguno,
        ),
        acumulada: 40,
        niveles: niveles,
      );

      expect(find.text('Nivel: aún sin nivel'), findsOneWidget);
      expect(find.text('Te faltan 60 XP para Bronce.'), findsOneWidget);
    });

    testWidgets('en el último nivel la barra queda llena', (tester) async {
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 25,
          ajuste: AjusteExperiencia.ninguno,
        ),
        acumulada: 2000,
        niveles: niveles,
      );

      expect(find.text('Nivel: Oro'), findsOneWidget);
      expect(find.text('Estás en el nivel más alto.'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(SeccionExperiencia.claveAvanceNivel),
            )
            .value,
        1,
      );
    });

    testWidgets('sin niveles creados no muestra nivel', (tester) async {
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 25,
          ajuste: AjusteExperiencia.ninguno,
        ),
        acumulada: 300,
      );

      expect(find.byKey(SeccionExperiencia.claveNivel), findsNothing);
      expect(total(tester), '+25 XP');
    });
  });

  group('aviso de ascenso (SCRUM-199)', () {
    const niveles = [_bronce, _plata, _oro];

    testWidgets('si el entrenamiento lo hizo subir, lo anuncia sin que haga '
        'nada', (tester) async {
      // Tenía 480; este entrenamiento dejó 30 y llegó a 510.
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 30,
          ajuste: AjusteExperiencia.ninguno,
        ),
        acumulada: 510,
        niveles: niveles,
        anunciarAscenso: true,
      );

      expect(find.byKey(SeccionExperiencia.claveAscenso), findsOneWidget);
      expect(find.text('¡Subiste a Plata!'), findsOneWidget);
      expect(find.text('Lo lograste con este entrenamiento.'), findsOneWidget);
      // No hay nada que confirmar ni cerrar.
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('si cruzó varios niveles, dice cuántos y a cuál llegó', (
      tester,
    ) async {
      // Un reto grande: de 120 a 1620.
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 100,
          ajuste: AjusteExperiencia.ninguno,
          retos: [RetoCompletado(nombre: 'Maratón del mes', xp: 1400)],
        ),
        acumulada: 1620,
        niveles: niveles,
        anunciarAscenso: true,
      );

      expect(find.text('¡Subiste 2 niveles!'), findsOneWidget);
      expect(
        find.text('Llegaste a Oro con este entrenamiento.'),
        findsOneWidget,
      );
    });

    testWidgets('sin llegar al siguiente umbral no anuncia nada', (
      tester,
    ) async {
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 30,
          ajuste: AjusteExperiencia.ninguno,
        ),
        acumulada: 400,
        niveles: niveles,
        anunciarAscenso: true,
      );

      expect(find.byKey(SeccionExperiencia.claveAscenso), findsNothing);
      expect(find.text('Nivel: Bronce'), findsOneWidget);
    });

    testWidgets('en el último nivel la XP nueva no inventa un ascenso', (
      tester,
    ) async {
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 125,
          ajuste: AjusteExperiencia.topeDiario,
        ),
        acumulada: 5000,
        niveles: niveles,
        anunciarAscenso: true,
      );

      expect(find.byKey(SeccionExperiencia.claveAscenso), findsNothing);
    });

    testWidgets('desde el historial no se anuncia', (tester) async {
      // La XP ganada después falsearía qué niveles cruzó este entrenamiento.
      await montar(
        tester,
        xp: const ExperienciaDeEntrenamiento(
          xpActividad: 30,
          ajuste: AjusteExperiencia.ninguno,
        ),
        acumulada: 510,
        niveles: niveles,
      );

      expect(find.byKey(SeccionExperiencia.claveAscenso), findsNothing);
      expect(find.text('Nivel: Plata'), findsOneWidget);
    });
  });
}
