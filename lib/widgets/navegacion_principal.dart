import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Secciones a las que se llega desde la barra inferior.
enum SeccionPrincipal {
  inicio(etiqueta: 'Inicio', icono: Icons.home_outlined, ruta: '/inicio'),
  historial(
    etiqueta: 'Historial',
    icono: Icons.schedule_outlined,
    ruta: '/historial',
  ),
  perfil(etiqueta: 'Perfil', icono: Icons.person_outline, ruta: '/perfil');

  const SeccionPrincipal({
    required this.etiqueta,
    required this.icono,
    required this.ruta,
  });

  final String etiqueta;
  final IconData icono;
  final String ruta;
}

/// Pone [child] sobre la barra de navegación del prototipo (`.bottom-nav`),
/// con el botón "+" flotante para arrancar una actividad.
///
/// El prototipo completo lleva seis secciones (Inicio, Progreso, Retos,
/// Rutas, Foro, Perfil); aquí están solo las tres que existen hoy. Las demás
/// se agregan a [SeccionPrincipal] cuando lleguen sus historias.
class NavegacionPrincipal extends StatelessWidget {
  const NavegacionPrincipal({
    required this.seccion,
    required this.child,
    this.onNuevaActividad,
    super.key,
  });

  /// En cuál de las secciones está el usuario: es la que se marca.
  final SeccionPrincipal seccion;

  final Widget child;

  /// Arranca una actividad nueva. Sin esto no se muestra el botón "+", que
  /// solo tiene sentido en la portada.
  final VoidCallback? onNuevaActividad;

  /// Alto de la barra (`.bottom-nav` del prototipo).
  static const alto = 82.0;

  static const claveBoton = Key('nav-nueva-actividad');

  @override
  Widget build(BuildContext context) {
    final onNuevaActividad = this.onNuevaActividad;

    return Scaffold(
      // El contenido llega hasta abajo y la barra flota encima, como en el
      // prototipo: por eso cada sección deja hueco al final.
      body: child,
      floatingActionButton: onNuevaActividad == null
          ? null
          : FloatingActionButton(
              key: claveBoton,
              onPressed: onNuevaActividad,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 6,
              tooltip: 'Nueva actividad',
              child: const Icon(Icons.add, size: 26),
            ),
      bottomNavigationBar: _Barra(seccion: seccion),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.seccion});

  final SeccionPrincipal seccion;

  void _ir(BuildContext context, SeccionPrincipal destino) {
    if (destino == seccion) return;
    // `go` y no `push`: las secciones no se apilan unas sobre otras.
    context.go(destino.ruta);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: NavegacionPrincipal.alto,
          child: Row(
            children: [
              for (final destino in SeccionPrincipal.values)
                Expanded(
                  child: _Item(
                    destino: destino,
                    activa: destino == seccion,
                    onTap: () => _ir(context, destino),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.destino,
    required this.activa,
    required this.onTap,
  });

  final SeccionPrincipal destino;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activa ? AppColors.primary : AppColors.ink3;

    return Semantics(
      button: true,
      selected: activa,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(destino.icono, size: 23, color: color),
              const SizedBox(height: 4),
              Text(
                destino.etiqueta,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
