import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/theme/app_colors.dart';
import 'package:traza/widgets/navegacion_principal.dart';

/// Pruebas de la barra inferior: marca la sección donde está el usuario,
/// lleva a las otras sin apilarlas y solo enseña el "+" a quien se lo pasa.
void main() {
  Future<GoRouter> montar(
    WidgetTester tester, {
    SeccionPrincipal seccion = SeccionPrincipal.inicio,
    VoidCallback? onNuevaActividad,
  }) async {
    Widget seccionDe(SeccionPrincipal cual) => NavegacionPrincipal(
      seccion: cual,
      onNuevaActividad: cual == seccion ? onNuevaActividad : null,
      child: Center(child: Text('Contenido de ${cual.etiqueta}')),
    );

    final router = GoRouter(
      initialLocation: seccion.ruta,
      routes: [
        for (final destino in SeccionPrincipal.values)
          GoRoute(
            path: destino.ruta,
            builder: (_, _) => seccionDe(destino),
          ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  Color colorDe(WidgetTester tester, String etiqueta) =>
      tester.widget<Text>(find.text(etiqueta)).style!.color!;

  testWidgets('tiene las tres secciones que existen hoy', (tester) async {
    await montar(tester);

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Historial'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
  });

  testWidgets('marca la sección donde está el usuario', (tester) async {
    await montar(tester, seccion: SeccionPrincipal.historial);

    expect(colorDe(tester, 'Historial'), AppColors.primary);
    expect(colorDe(tester, 'Inicio'), AppColors.ink3);
    expect(colorDe(tester, 'Perfil'), AppColors.ink3);
  });

  testWidgets('tocar otra sección lleva a su ruta', (tester) async {
    final router = await montar(tester);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Contenido de Perfil'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/perfil',
    );
  });

  testWidgets('las secciones no se apilan: cambiar de una a otra no deja '
      'nada atrás', (tester) async {
    final router = await montar(tester);

    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.matches.length, 1);
  });

  testWidgets('tocar la sección donde ya está no navega', (tester) async {
    final router = await montar(tester);

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/inicio');
    expect(find.text('Contenido de Inicio'), findsOneWidget);
  });

  group('botón "+"', () {
    testWidgets('sin acción no se muestra: solo la portada lo lleva', (
      tester,
    ) async {
      await montar(tester);

      expect(find.byKey(NavegacionPrincipal.claveBoton), findsNothing);
    });

    testWidgets('con acción se muestra y la ejecuta al tocarlo', (
      tester,
    ) async {
      var toques = 0;
      await montar(tester, onNuevaActividad: () => toques++);

      await tester.tap(find.byKey(NavegacionPrincipal.claveBoton));
      await tester.pump();

      expect(toques, 1);
    });
  });
}
