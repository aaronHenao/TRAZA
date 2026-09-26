import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nivel.dart';
import 'package:traza/screens/admin/formulario_nivel_screen.dart';
import 'package:traza/screens/admin/gestion_niveles_screen.dart';
import 'package:traza/services/niveles_provider.dart';
import 'package:traza/services/niveles_service.dart';
import 'package:traza/services/retos_service.dart'
    show SoloAdministradorException;

import '../utiles/niveles_falso.dart';

/// Pruebas del formulario de creación de niveles (SCRUM-182), con los mensajes
/// de cada validación (SCRUM-181).
void main() {
  const existentes = [
    Nivel(id: 'n-1', nombre: 'Bronce', umbralExperiencia: 100),
    Nivel(id: 'n-2', nombre: 'Plata', umbralExperiencia: 500),
  ];

  Future<void> escribir(
    WidgetTester tester, {
    required String nombre,
    required String umbral,
  }) async {
    await tester.enterText(find.byType(TextField).first, nombre);
    await tester.enterText(find.byType(TextField).last, umbral);
    await tester.pump();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.tap(find.byKey(FormularioNivelScreen.claveGuardar));
    await tester.pumpAndSettle();
  }

  testWidgets('sin datos señala los dos campos y no toca la base', (
    tester,
  ) async {
    final repositorio = await _montar(tester);

    await guardar(tester);

    expect(find.text('Ponle un nombre al nivel.'), findsOneWidget);
    expect(
      find.text('Indica la experiencia necesaria para alcanzarlo.'),
      findsOneWidget,
    );
    expect(repositorio.recibido, isNull);
  });

  testWidgets('rechaza el umbral en cero', (tester) async {
    await _montar(tester);

    await escribir(tester, nombre: 'Oro', umbral: '0');
    await guardar(tester);

    expect(find.text('El umbral debe ser mayor que cero.'), findsOneWidget);
  });

  testWidgets('dice con qué nivel se solapa el umbral', (tester) async {
    await _montar(tester, catalogo: existentes);

    await escribir(tester, nombre: 'Oro', umbral: '500');
    await guardar(tester);

    expect(
      find.text(
        'Ese umbral ya lo usa "Plata". Cada nivel empieza en uno distinto.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('dice con qué nivel se repite el nombre', (tester) async {
    await _montar(tester, catalogo: existentes);

    await escribir(tester, nombre: 'bronce', umbral: '1500');
    await guardar(tester);

    expect(find.text('Ya existe un nivel llamado "Bronce".'), findsOneWidget);
  });

  testWidgets('el error se quita en cuanto se corrige el campo', (
    tester,
  ) async {
    await _montar(tester);

    await guardar(tester);
    expect(find.text('Ponle un nombre al nivel.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Oro');
    await tester.pump();

    expect(find.text('Ponle un nombre al nivel.'), findsNothing);
  });

  testWidgets('con los datos bien crea el nivel y vuelve al listado', (
    tester,
  ) async {
    final repositorio = await _montar(tester, catalogo: existentes);

    await escribir(tester, nombre: '  Oro  ', umbral: '1500');
    await guardar(tester);

    // El nombre se guarda sin los espacios de los extremos.
    expect(repositorio.recibido?.nombre, 'Oro');
    expect(repositorio.recibido?.umbralExperiencia, 1500);

    // De vuelta en la gestión, con el nivel recién creado ya en la lista.
    expect(find.byType(GestionNivelesScreen), findsOneWidget);
    expect(find.text('Oro'), findsOneWidget);
  });

  testWidgets('si otro se adelantó con ese umbral, lo marca sin perder lo '
      'escrito', (tester) async {
    final repositorio = await _montar(tester);
    repositorio.errorAlCrear = const NivelDuplicadoException.porUmbral();

    await escribir(tester, nombre: 'Oro', umbral: '1500');
    await guardar(tester);

    expect(find.text(CreacionNivel.umbralOcupado), findsOneWidget);
    expect(find.byType(FormularioNivelScreen), findsOneWidget);
    expect(find.text('Oro'), findsOneWidget);
  });

  testWidgets('si la cuenta no es administradora, avisa y conserva el '
      'formulario', (tester) async {
    final repositorio = await _montar(tester);
    repositorio.errorAlCrear = const SoloAdministradorException();

    await escribir(tester, nombre: 'Oro', umbral: '1500');
    await guardar(tester);

    expect(find.text(CreacionNivel.soloAdministrador), findsOneWidget);
    expect(find.byType(FormularioNivelScreen), findsOneWidget);

    // El aviso desaparece solo; se espera para no dejar su temporizador vivo.
    await tester.pump(const Duration(seconds: 3));
  });
}

/// Abre la gestión de niveles y entra al formulario, que es como se llega en
/// la app. Devuelve el repositorio falso para revisar qué se guardó.
Future<NivelesFalso> _montar(
  WidgetTester tester, {
  List<Nivel> catalogo = const [],
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repositorio = NivelesFalso(catalogo: catalogo);

  final router = GoRouter(
    initialLocation: GestionNivelesScreen.ruta,
    routes: [
      GoRoute(
        path: GestionNivelesScreen.ruta,
        builder: (_, _) => const GestionNivelesScreen(),
        routes: [
          GoRoute(
            path: 'nuevo',
            builder: (_, _) => const FormularioNivelScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [nivelesRepositoryProvider.overrideWithValue(repositorio)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(GestionNivelesScreen.claveBotonNuevo));
  await tester.pumpAndSettle();

  return repositorio;
}
