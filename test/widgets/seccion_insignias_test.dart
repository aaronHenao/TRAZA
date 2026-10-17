import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/insignia.dart';
import 'package:traza/services/insignias_service.dart';
import 'package:traza/services/objetivos_service.dart'
    show SesionRequeridaException;
import 'package:traza/widgets/seccion_insignias.dart';

import '../utiles/insignias_falsas.dart';

final _primeraHuella = Insignia(
  id: 'i-1',
  nombre: 'Primera huella',
  descripcion: 'Tu primer kilómetro con TRAZA',
  icono: 'huella',
  xpRequerida: 5,
  obtenidaEl: DateTime.utc(2026, 9, 20, 15),
);
final _enRacha = Insignia(
  id: 'i-2',
  nombre: 'En racha',
  descripcion: 'Suma tus primeros 30 XP',
  icono: 'fuego',
  xpRequerida: 30,
  obtenidaEl: DateTime.utc(2026, 9, 22, 12),
);
const _diezMil = Insignia(
  id: 'i-3',
  nombre: 'Diez mil',
  descripcion: 'Tus primeros 10 km en una salida',
  icono: 'diez',
  xpRequerida: 105,
);

/// Pruebas de las insignias en la información del corredor (SCRUM-193,
/// criterio 6).
///
/// Quién las otorga es el trigger de la base (criterios 1 a 5); la sección solo
/// muestra el catálogo con las que ya tiene marcadas.
void main() {
  Future<InsigniasFalsas> montar(
    WidgetTester tester, {
    List<Insignia> catalogo = const [],
    Object? error,
    Size tamano = const Size(390, 844),
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final falsas = InsigniasFalsas(catalogo: catalogo)..error = error;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [insigniasRepositoryProvider.overrideWithValue(falsas)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SeccionInsignias()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return falsas;
  }

  Finder dentroDe(String id, Finder buscado) => find.descendant(
    of: find.byKey(ValueKey('insignia-$id')),
    matching: buscado,
  );

  group('criterio 6: las insignias obtenidas se ven', () {
    testWidgets('una insignia obtenida muestra su nombre, su descripción y '
        'que ya es suya', (tester) async {
      await montar(tester, catalogo: [_primeraHuella, _diezMil]);

      expect(find.byKey(SeccionInsignias.clave), findsOneWidget);
      expect(dentroDe('i-1', find.text('Primera huella')), findsOneWidget);
      expect(
        dentroDe('i-1', find.text('Tu primer kilómetro con TRAZA')),
        findsOneWidget,
      );
      expect(dentroDe('i-1', find.text('Obtenida')), findsOneWidget);
    });

    testWidgets('una insignia pendiente muestra cuánta XP pide y no aparece '
        'como obtenida', (tester) async {
      await montar(tester, catalogo: [_primeraHuella, _diezMil]);

      expect(dentroDe('i-3', find.text('Diez mil')), findsOneWidget);
      expect(dentroDe('i-3', find.text('105 XP')), findsOneWidget);
      expect(dentroDe('i-3', find.text('Obtenida')), findsNothing);
    });

    testWidgets('dibuja cada insignia del catálogo, obtenida o no', (
      tester,
    ) async {
      await montar(tester, catalogo: [_primeraHuella, _enRacha, _diezMil]);

      for (final id in ['i-1', 'i-2', 'i-3']) {
        expect(
          find.byKey(ValueKey('insignia-$id')),
          findsOneWidget,
          reason: id,
        );
      }
      expect(find.text('Obtenida'), findsNWidgets(2));
    });
  });

  group('encabezado', () {
    testWidgets('dice cuántas lleva de cuántas hay', (tester) async {
      await montar(tester, catalogo: [_primeraHuella, _enRacha, _diezMil]);

      expect(find.text('INSIGNIAS'), findsOneWidget);
      expect(find.text('2 de 3'), findsOneWidget);
    });

    testWidgets('sin ninguna obtenida el conteo empieza en cero', (
      tester,
    ) async {
      await montar(tester, catalogo: const [_diezMil]);

      expect(find.byKey(SeccionInsignias.clave), findsOneWidget);
      expect(find.text('0 de 1'), findsOneWidget);
      expect(find.text('Obtenida'), findsNothing);
    });

    testWidgets('con todas obtenidas el conteo queda completo', (tester) async {
      await montar(tester, catalogo: [_primeraHuella, _enRacha]);

      expect(find.text('2 de 2'), findsOneWidget);
    });
  });

  testWidgets('con el catálogo vacío no dibuja nada', (tester) async {
    await montar(tester, catalogo: const []);

    expect(find.byKey(SeccionInsignias.clave), findsNothing);
    expect(find.text('INSIGNIAS'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('si no carga', () {
    testWidgets('avisa sin mostrar el error técnico y deja volver a '
        'intentar', (tester) async {
      final falsas = await montar(
        tester,
        catalogo: [_primeraHuella],
        error: StateError('Supabase no disponible'),
      );

      expect(find.text('No pudimos cargar tus insignias'), findsOneWidget);
      expect(find.textContaining('Supabase'), findsNothing);
      expect(falsas.consultas, 1);

      falsas.error = null;
      await tester.tap(find.text('Volver a intentar'));
      await tester.pumpAndSettle();

      expect(falsas.consultas, 2);
      expect(find.text('No pudimos cargar tus insignias'), findsNothing);
      expect(dentroDe('i-1', find.text('Obtenida')), findsOneWidget);
    });

    testWidgets('sin sesión también avisa en vez de fallar', (tester) async {
      await montar(
        tester,
        catalogo: [_primeraHuella],
        error: const SesionRequeridaException(),
      );

      expect(find.text('No pudimos cargar tus insignias'), findsOneWidget);
      expect(find.text('Volver a intentar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('en cualquier pantalla', () {
    // Las nueve claves de icono del catálogo inicial, con nombres largos.
    const claves = [
      'huella',
      'fuego',
      'diez',
      'media',
      'maraton',
      'calle',
      'primavera',
      'colombia',
      'leyenda',
    ];
    final catalogoCompleto = [
      for (final (i, clave) in claves.indexed)
        Insignia(
          id: 'i-$i',
          nombre: 'Corredor incansable de madrugadas interminables $i',
          descripcion:
              'Una descripción bastante larga para ver que el texto se '
              'acomoda sin salirse de la tarjeta $i',
          icono: clave,
          xpRequerida: 5 + i * 100,
          obtenidaEl: i.isEven ? DateTime.utc(2026, 9, 20 + i % 5) : null,
        ),
    ];

    testWidgets('el catálogo completo no desborda en la pantalla más '
        'estrecha', (tester) async {
      await montar(
        tester,
        catalogo: catalogoCompleto,
        tamano: const Size(320, 568),
      );

      expect(find.byKey(SeccionInsignias.clave), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('una clave de icono que la app no conoce no rompe la '
        'sección', (tester) async {
      // El catálogo vive en la base: puede llegar una insignia nueva antes
      // que la versión de la app que conoce su icono.
      await montar(
        tester,
        catalogo: const [
          Insignia(
            id: 'i-9',
            nombre: 'Insignia del futuro',
            descripcion: 'Todavía no existe en esta versión',
            icono: 'desconocido',
            xpRequerida: 9000,
          ),
        ],
      );

      expect(dentroDe('i-9', find.text('Insignia del futuro')), findsOneWidget);
      expect(
        dentroDe('i-9', find.byIcon(Icons.verified_outlined)),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
