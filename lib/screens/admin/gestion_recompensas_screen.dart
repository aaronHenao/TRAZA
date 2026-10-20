import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/recompensa.dart';
import '../../services/recompensas_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_recompensa.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Las recompensas que administra el administrador (SCRUM-374): todas,
/// disponibles o no, el botón para crear una nueva y, en cada tarjeta, el de
/// cambiar sus puntos (SCRUM-380).
class GestionRecompensasScreen extends ConsumerWidget {
  const GestionRecompensasScreen({super.key});

  static const ruta = '/admin/recompensas';
  static const rutaNueva = '$ruta/nueva';

  static const claveBotonNueva = Key('admin-nueva-recompensa');

  // Cambiar los puntos (SCRUM-380).
  static Key claveCambiarPuntos(String id) => Key('cambiar-puntos-$id');
  static const claveCampoPuntos = Key('cambiar-puntos-campo');
  static const claveGuardarPuntos = Key('cambiar-puntos-guardar');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recompensas = ref.watch(gestionRecompensasProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: claveBotonNueva,
        // `push`: al volver del formulario se regresa aquí, y la lista se
        // refresca con la recompensa recién creada.
        onPressed: () async {
          await context.push(rutaNueva);
          ref.invalidate(gestionRecompensasProvider);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Nueva recompensa',
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(
                titulo: 'Gestión de recompensas',
                // Se llega desde el panel del administrador; si se abrió la
                // ruta directamente no hay a dónde volver.
                onAtras: context.canPop() ? context.pop : null,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Text(
                  'Lo que los corredores pueden obtener con sus puntos',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(gestionRecompensasProvider),
                  child: switch (recompensas) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      const EstadoVacio(
                        icono: Icons.card_giftcard_outlined,
                        titulo: 'Todavía no hay recompensas',
                        detalle:
                            'Crea la primera con el botón +. Las disponibles '
                            'aparecen en el catálogo de los corredores.',
                      ),
                    AsyncData(value: final lista) => _Lista(recompensas: lista),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar las recompensas',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: () =>
                            ref.invalidate(gestionRecompensasProvider),
                        child: const Text('Reintentar'),
                      ),
                    ),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.recompensas});

  final List<Recompensa> recompensas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // Hueco al final para que el botón + no tape la última tarjeta.
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 96),
      itemCount: recompensas.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final recompensa = recompensas[i];
        return TarjetaRecompensa(
          key: TarjetaRecompensa.claveDe(recompensa.id),
          recompensa: recompensa,
          conDisponibilidad: true,
          acciones: [
            TextButton.icon(
              key: GestionRecompensasScreen.claveCambiarPuntos(recompensa.id),
              onPressed: () => _cambiarPuntos(context, ref, recompensa),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Cambiar puntos'),
            ),
          ],
        );
      },
    );
  }
}

/// Pide los puntos nuevos y los guarda (SCRUM-380).
///
/// Lo inválido no sale del diálogo (criterio 2). Si el guardado falla, la
/// lista no se recarga y sigue mostrando el valor anterior.
Future<void> _cambiarPuntos(
  BuildContext context,
  WidgetRef ref,
  Recompensa recompensa,
) async {
  final texto = await showDialog<String>(
    context: context,
    builder: (_) => _DialogoPuntos(recompensa: recompensa),
  );
  if (texto == null || !context.mounted) return;

  final resultado = await ref
      .read(cambioPuntosRecompensaProvider)
      .cambiar(recompensa, texto);
  if (!context.mounted) return;

  mostrarToast(context, switch (resultado) {
    // La lista se rehace sola: `cambiar` invalida la gestión.
    PuntosCambiados() => 'Puntos actualizados',
    PuntosInvalidos(:final mensaje) => mensaje,
    PuntosNoGuardados(:final mensaje) => mensaje,
  });
}

/// El campo con los puntos actuales ya escritos. Valida antes de cerrar, así
/// una cantidad inválida se corrige ahí mismo.
class _DialogoPuntos extends StatefulWidget {
  const _DialogoPuntos({required this.recompensa});

  final Recompensa recompensa;

  @override
  State<_DialogoPuntos> createState() => _DialogoPuntosState();
}

class _DialogoPuntosState extends State<_DialogoPuntos> {
  late final _puntos = TextEditingController(
    text: '${widget.recompensa.puntosRequeridos}',
  );
  String? _error;

  @override
  void dispose() {
    _puntos.dispose();
    super.dispose();
  }

  void _guardar() {
    final error = errorDePuntos(_puntos.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_puntos.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar puntos'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.recompensa.nombre}. Los canjes ya hechos conservan lo '
            'que costaron.',
            style: const TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: GestionRecompensasScreen.claveCampoPuntos,
            controller: _puntos,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _guardar(),
            decoration: InputDecoration(
              suffixText: 'puntos',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: GestionRecompensasScreen.claveGuardarPuntos,
          onPressed: _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
