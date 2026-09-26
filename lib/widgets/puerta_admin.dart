import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/admin/panel_admin_screen.dart';
import '../services/rol_provider.dart';

/// Decide qué ve cada cuenta al entrar: el administrador su panel
/// (SCRUM-194), los corredores su portada (SCRUM-139).
///
/// Es un widget y no un `redirect` del router porque leer `perfiles.rol`
/// es asíncrono y el redirect de go_router es síncrono. Renderizar en vez de
/// navegar también evita el parpadeo de entrar a una pantalla y salir de ella
/// enseguida.
///
/// Que el administrador no vea la portada es presentación, nada más: quien
/// impide que un corredor escriba en `retos` es RLS.
class PuertaAdmin extends ConsumerWidget {
  const PuertaAdmin({required this.corredor, super.key});

  /// Lo que se muestra a una cuenta normal.
  final Widget corredor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(esAdministradorProvider)) {
      AsyncData(value: true) => const PanelAdminScreen(),
      AsyncData() => corredor,
      // Si el rol no se pudo leer, se entra como corredor. Al revés se
      // abrirían pantallas de gestión que después no podrían guardar nada.
      AsyncError() => corredor,
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
