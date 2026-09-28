import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/experiencia_ganada.dart';
import 'package:traza/models/regla_experiencia.dart';
import 'package:traza/services/experiencia_service.dart';
import 'package:traza/widgets/seccion_experiencia.dart';

import '../utiles/experiencia_falsa.dart';

/// Pruebas de la XP en el resumen del entrenamiento (SCRUM-207).
void main() {
  Future<ExperienciaFalsa> montar(
    WidgetTester tester, {
    ExperienciaDeEntrenamiento? xp,
    Object? error,
  }) async {
    final falsa = ExperienciaFalsa(porEntrenamiento: {'e-1': ?xp})
      ..error = error;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [experienciaRepositoryProvider.overrideWithValue(falsa)],
        child: const MaterialApp(
          home: Scaffold(body: SeccionExperiencia(entrenamientoId: 'e-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return falsa;
  }

  String total(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(SeccionExperiencia.claveTotal)).data!;

  testWidgets('muestra la XP obtenida por la actividad', (tester) async {
    await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 25,
        ajuste: AjusteExperiencia.ninguno,
      ),
    );

    expect(find.text('XP obtenida'), findsOneWidget);
    expect(total(tester), '+25 XP');
    // Sin retos, el desglose sobraría.
    expect(find.text('Actividad'), findsNothing);
  });

  testWidgets('siempre avisa cuánto da la actividad como máximo al día', (
    tester,
  ) async {
    await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 25,
        ajuste: AjusteExperiencia.ninguno,
      ),
    );

    expect(
      find.text(
        'La actividad da hasta 125 XP al día (25 km). '
        'Los retos no tienen tope.',
      ),
      findsOneWidget,
    );
    // El número sale de la regla, no está escrito aparte.
    expect(
      SeccionExperiencia.notaTope,
      contains('${ReglaExperiencia.topeDiarioXp} XP'),
    );
  });

  testWidgets('con un reto completado, desglosa actividad y reto', (
    tester,
  ) async {
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
    expect(find.text('Reto «Diez km» completado'), findsOneWidget);
    expect(find.text('+400 XP'), findsOneWidget);
  });

  testWidgets('al llegar al tope explica que los km siguen contando', (
    tester,
  ) async {
    await montar(
      tester,
      xp: const ExperienciaDeEntrenamiento(
        xpActividad: 0,
        ajuste: AjusteExperiencia.topeDiario,
      ),
    );

    expect(total(tester), '+0 XP');
    expect(
      find.text(
        'Llegaste al tope de XP del día. '
        'Tus km siguen contando para tus retos.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('explica por qué una actividad no sumó XP', (tester) async {
    const esperados = {
      AjusteExperiencia.menosDelMinimo:
          'La actividad suma XP desde el primer kilómetro.',
      AjusteExperiencia.velocidadImposible:
          'El promedio superó los 25 km/h, así que esta actividad no suma XP.',
      AjusteExperiencia.sinDatos:
          'Sin distancia registrada, esta actividad no suma XP.',
    };

    for (final MapEntry(key: ajuste, value: texto) in esperados.entries) {
      await montar(
        tester,
        xp: ExperienciaDeEntrenamiento(xpActividad: 0, ajuste: ajuste),
      );
      expect(find.text(texto), findsOneWidget, reason: ajuste.name);
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
}
