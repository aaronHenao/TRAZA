import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/periodicidad_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/screens/admin/formulario_reto_screen.dart';
import 'package:traza/screens/admin/gestion_retos_screen.dart';
import 'package:traza/services/reloj_provider.dart';
import 'package:traza/services/retos_service.dart';
import 'package:traza/widgets/ancho_contenido.dart';

class _RetosFalso implements RetosRepository {
  _RetosFalso(this.retos);

  final List<Reto> retos;

  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async =>
      retos.where((reto) => reto.estado == estado).toList();

  @override
  Future<Reto> crear(NuevoReto reto) async => throw UnimplementedError();
}

/// Las pantallas del administrador en los anchos de pantalla que se van a
/// usar de verdad, y con el texto del sistema agrandado.
///
/// Un desbordamiento de layout hace fallar la prueba por sí solo, así que
/// montar cada pantalla en cada tamaño ya es la comprobación. Lo demás son
/// las decisiones que dependen del ancho.
void main() {
  final ahora = DateTime(2026, 9, 23, 11, 30);

  // Anchos reales: el más estrecho que se sigue vendiendo, el Android común,
  // un iPhone actual, un teléfono grande y una tableta pequeña.
  const tamanos = {
    'estrecho': Size(320, 568),
    'común': Size(360, 640),
    'normal': Size(390, 844),
    'grande': Size(430, 932),
    'tableta': Size(768, 1024),
  };

  Reto reto(String id, String nombre, PeriodicidadReto periodicidad) => Reto(
    id: id,
    nombre: nombre,
    descripcion: 'Una descripción larga de $nombre, con condiciones y todo.',
    periodicidad: periodicidad,
    metaKm: 15.5,
    xpOtorgada: 2000,
    vigencia: periodicidad.vigenciaDesde(ahora),
    estado: EstadoReto.activo,
  );

  final catalogo = [
    reto('1', 'Corre 5 km hoy sin parar en el camino', PeriodicidadReto.diaria),
    reto('2', 'Corre 15 km esta semana', PeriodicidadReto.semanal),
    reto('3', 'Mes de 60 km acumulados', PeriodicidadReto.mensual),
  ];

  Future<void> montar(
    WidgetTester tester,
    Size tamano,
    Widget pantalla, {
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = tamano * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/pantalla',
      routes: [
        GoRoute(path: '/pantalla', builder: (_, _) => pantalla),
        GoRoute(
          path: '/admin/retos/nuevo',
          builder: (_, _) => const Scaffold(body: Text('Formulario')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retosRepositoryProvider.overrideWithValue(_RetosFalso(catalogo)),
          relojProvider.overrideWithValue(() => ahora),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(escalaTexto)),
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('la gestión de retos entra en cualquier pantalla', () {
    for (final tamano in tamanos.entries) {
      testWidgets('ancho ${tamano.key}', (tester) async {
        await montar(tester, tamano.value, const GestionRetosScreen());

        expect(find.text('Gestión de retos'), findsOneWidget);
        // Cuántos caben depende del alto: lo que se comprueba es que la
        // pantalla se arma entera sin desbordar.
        expect(find.byType(TarjetaReto), findsWidgets);
      });

      testWidgets('ancho ${tamano.key} con el texto del sistema grande', (
        tester,
      ) async {
        await montar(
          tester,
          tamano.value,
          const GestionRetosScreen(),
          escalaTexto: 1.3,
        );

        expect(find.text('Gestión de retos'), findsOneWidget);
      });
    }

    testWidgets('los cuatro filtros se ven enteros, hasta en 320 px', (
      tester,
    ) async {
      await montar(tester, tamanos['estrecho']!, const GestionRetosScreen());

      // Saltan de línea en vez de salirse: un chip cortado en el borde no se
      // ve como algo que se pueda arrastrar.
      for (final opcion in <PeriodicidadReto?>[
        null,
        ...PeriodicidadReto.values,
      ]) {
        final chip = find.byKey(GestionRetosScreen.clavePeriodicidad(opcion));
        final nombre = opcion?.etiqueta ?? 'Todos';
        expect(chip, findsOneWidget, reason: nombre);
        expect(
          tester.getBottomRight(chip).dx,
          lessThanOrEqualTo(320),
          reason: '$nombre se sale de la pantalla',
        );
        // Y ninguno se estira a todo el ancho: son chips, no botones de
        // lista, así que caben varios por línea.
        expect(
          tester.getSize(chip).width,
          lessThan(200),
          reason: '$nombre ocupa la línea entera',
        );
      }
    });
  });

  group('el formulario entra en cualquier pantalla', () {
    for (final tamano in tamanos.entries) {
      testWidgets('ancho ${tamano.key}', (tester) async {
        await montar(tester, tamano.value, const FormularioRetoScreen());

        // Con la periodicidad elegida aparecen la vigencia y su aviso, que
        // son los textos más largos de la pantalla.
        await tester.tap(find.text('Mensual'));
        await tester.pumpAndSettle();

        expect(find.byKey(FormularioRetoScreen.claveGuardar), findsOneWidget);
      });

      testWidgets('ancho ${tamano.key} con el texto del sistema grande', (
        tester,
      ) async {
        await montar(
          tester,
          tamano.value,
          const FormularioRetoScreen(),
          escalaTexto: 1.3,
        );

        await tester.tap(find.text('Semanal'));
        await tester.pumpAndSettle();

        expect(find.byKey(FormularioRetoScreen.claveGuardar), findsOneWidget);
      });
    }

    /// Los campos numéricos están al final del formulario: en pantallas
    /// bajas hay que desplazarse hasta ellos antes de medirlos.
    Future<void> bajarHastaXp(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('XP otorgada'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('en 320 px meta y XP se apilan en vez de apretarse', (
      tester,
    ) async {
      await montar(tester, tamanos['estrecho']!, const FormularioRetoScreen());
      await bajarHastaXp(tester);

      expect(
        tester.getTopLeft(find.text('XP otorgada')).dy,
        greaterThan(tester.getTopLeft(find.text('Meta')).dy),
      );
    });

    testWidgets('en un ancho normal van lado a lado', (tester) async {
      await montar(tester, tamanos['normal']!, const FormularioRetoScreen());
      await bajarHastaXp(tester);

      expect(
        tester.getTopLeft(find.text('XP otorgada')).dy,
        tester.getTopLeft(find.text('Meta')).dy,
      );
    });
  });

  group('pantallas anchas', () {
    testWidgets('el contenido no se estira de lado a lado en una tableta', (
      tester,
    ) async {
      await montar(tester, tamanos['tableta']!, const FormularioRetoScreen());

      // Sin tope, los campos medirían 768 px y el formulario se leería mal.
      expect(
        tester.getSize(find.byType(AnchoContenido).first).width,
        greaterThan(AnchoContenido.maximo),
      );
      expect(
        tester.getSize(find.byKey(FormularioRetoScreen.claveGuardar)).width,
        lessThanOrEqualTo(AnchoContenido.maximo),
      );
    });

    testWidgets('en un teléfono el tope no recorta nada', (tester) async {
      await montar(tester, tamanos['normal']!, const FormularioRetoScreen());

      expect(
        tester.getSize(find.byKey(FormularioRetoScreen.claveGuardar)).width,
        greaterThan(300),
      );
    });
  });
}
