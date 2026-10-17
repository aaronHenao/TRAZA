import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/foro_provider.dart';
import '../../services/foro_service.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/traza_top_bar.dart';
import 'nueva_publicacion_screen.dart';

/// Editar una publicación propia (SCRUM-355).
///
/// Pide la publicación por id, como el detalle, y abre el mismo formulario de
/// publicar ya lleno. Si no es del usuario o ya no está publicada, lo dice en
/// vez de ofrecer un formulario que la base no dejaría guardar.
class EditarPublicacionScreen extends ConsumerWidget {
  const EditarPublicacionScreen({required this.publicacionId, super.key});

  final String publicacionId;

  static const noEditable = 'Esta publicación ya no se puede editar';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final publicacion = ref.watch(publicacionForoProvider(publicacionId));
    final usuario = ref.read(usuarioActualProvider)();

    return switch (publicacion) {
      AsyncData(value: final p?) when p.editablePor(usuario) =>
        NuevaPublicacionScreen(editando: p),
      AsyncData() => _Aviso(
        child: EstadoVacio(
          icono: Icons.edit_off_outlined,
          titulo: noEditable,
          detalle: 'Solo su autor la edita, y solo mientras esté publicada.',
          accion: OutlinedButton(
            onPressed: context.pop,
            child: const Text('Volver'),
          ),
        ),
      ),
      AsyncError() => _Aviso(
        child: EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No pudimos cargar la publicación',
          detalle: 'Revisa tu conexión e inténtalo de nuevo.',
          accion: OutlinedButton(
            onPressed: () =>
                ref.invalidate(publicacionForoProvider(publicacionId)),
            child: const Text('Reintentar'),
          ),
        ),
      ),
      _ => const _Aviso(child: Center(child: CircularProgressIndicator())),
    };
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Editar publicación', onAtras: context.pop),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
