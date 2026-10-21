import 'package:flutter/material.dart';

import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/navegacion_principal.dart';
import '../../widgets/traza_top_bar.dart';

/// Rutas de la comunidad (SCRUM-284).
///
/// Provisional a propósito: la sección existe para que la barra sea la del
/// prototipo, pero lo que muestra —las rutas cercanas, su búsqueda y sus
/// filtros— lo construyen HU-29, HU-30, HU-36 y HU-37, que esperan a que
/// alguien pueda publicar rutas (HU-38).
///
/// Quien tome esa historia reemplaza el cuerpo de esta pantalla; la ruta, la
/// entrada en la barra y el título ya están puestos.
class RutasScreen extends StatelessWidget {
  const RutasScreen({super.key});

  static const ruta = '/rutas';

  @override
  Widget build(BuildContext context) {
    return NavegacionPrincipal(
      seccion: SeccionPrincipal.rutas,
      child: SafeArea(
        bottom: false,
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TrazaTopBar(titulo: 'Rutas'),
              const Expanded(
                child: Padding(
                  // Hueco para que el botón "+" no tape el mensaje.
                  padding: EdgeInsets.only(bottom: 96),
                  child: EstadoVacio(
                    icono: Icons.map_outlined,
                    titulo: 'Las rutas llegan pronto',
                    detalle:
                        'Aquí vas a ver los recorridos que publique la '
                        'comunidad, con su dificultad y su distancia.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
