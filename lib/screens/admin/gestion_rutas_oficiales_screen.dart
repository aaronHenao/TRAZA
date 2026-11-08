import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/ruta.dart';
import '../../models/ruta_oficial.dart';
import '../../services/rutas_oficiales_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_ruta_explorar.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// El camino del mapa de progresión que arma el administrador (rutas
/// oficiales, etapa 1): qué rutas publicadas entran y en qué orden.
class GestionRutasOficialesScreen extends ConsumerWidget {
  const GestionRutasOficialesScreen({super.key});

  static const ruta = '/admin/rutas-oficiales';

  static const claveBotonAgregar = Key('admin-agregar-ruta-oficial');
  static Key claveFila(String rutaId) => Key('ruta-oficial-$rutaId');
  static Key claveCandidata(String rutaId) =>
      Key('candidata-ruta-oficial-$rutaId');
  static Key claveSubir(String rutaId) => Key('subir-ruta-oficial-$rutaId');
  static Key claveBajar(String rutaId) => Key('bajar-ruta-oficial-$rutaId');
  static Key claveQuitar(String rutaId) => Key('quitar-ruta-oficial-$rutaId');
  static const claveConfirmarQuitar = Key('quitar-ruta-oficial-confirmar');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oficiales = ref.watch(rutasOficialesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: claveBotonAgregar,
        onPressed: () => _agregar(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Agregar ruta oficial',
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(
                titulo: 'Mapa de rutas oficiales',
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
                  'Las rutas que los corredores recorren en el mapa, en orden',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(rutasOficialesProvider),
                  child: switch (oficiales) {
                    AsyncData(value: final lista) when lista.isEmpty =>
                      const EstadoVacio(
                        icono: Icons.map_outlined,
                        titulo: 'Aún no hay rutas oficiales',
                        detalle:
                            'Agrega rutas publicadas con el botón + para '
                            'armar el mapa de los corredores.',
                      ),
                    AsyncData(value: final lista) => _Lista(oficiales: lista),
                    AsyncError() => EstadoVacio(
                      icono: Icons.cloud_off_outlined,
                      titulo: 'No pudimos cargar las rutas oficiales',
                      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
                      accion: OutlinedButton(
                        onPressed: () => ref.invalidate(rutasOficialesProvider),
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
  const _Lista({required this.oficiales});

  final List<RutaOficial> oficiales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gestion = ref.read(gestionRutasOficialesProvider);
    final ultima = oficiales.length - 1;

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // Hueco al final para que el botón + no tape la última tarjeta.
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 96),
      itemCount: oficiales.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final oficial = oficiales[i];
        final id = oficial.ruta.id;
        return _Fila(
          key: GestionRutasOficialesScreen.claveFila(id),
          oficial: oficial,
          // La primera no sube y la última no baja (criterio 4).
          onSubir: i == 0
              ? null
              : () => _avisar(context, gestion.subir(oficial)),
          onBajar: i == ultima
              ? null
              : () => _avisar(context, gestion.bajar(oficial)),
          onQuitar: () => _quitar(context, ref, oficial),
        );
      },
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.oficial,
    required this.onSubir,
    required this.onBajar,
    required this.onQuitar,
    super.key,
  });

  final RutaOficial oficial;
  final VoidCallback? onSubir;
  final VoidCallback? onBajar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final ruta = oficial.ruta;
    final id = ruta.id;

    return TrazaCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryTint,
            child: Text(
              '${oficial.posicion}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ruta.nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Por ${ruta.autorNombre}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
                ),
                const SizedBox(height: 2),
                Text(
                  TarjetaRutaExplorar.distanciaYDificultad(ruta),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          IconButton(
            key: GestionRutasOficialesScreen.claveSubir(id),
            onPressed: onSubir,
            tooltip: 'Subir',
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            key: GestionRutasOficialesScreen.claveBajar(id),
            onPressed: onBajar,
            tooltip: 'Bajar',
            icon: const Icon(Icons.arrow_downward),
          ),
          IconButton(
            key: GestionRutasOficialesScreen.claveQuitar(id),
            onPressed: onQuitar,
            tooltip: 'Quitar del mapa',
            color: AppColors.danger,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

/// Muestra el mensaje de la acción si falló. Si salió bien, la lista se
/// rehace sola: la acción la vuelve a consultar.
Future<void> _avisar(BuildContext context, Future<String?> accion) async {
  final mensaje = await accion;
  if (mensaje != null && context.mounted) mostrarToast(context, mensaje);
}

/// Ofrece las publicadas que todavía no están en el mapa y agrega la que se
/// elija al final (criterio 3).
Future<void> _agregar(BuildContext context, WidgetRef ref) async {
  final elegida = await showModalBottomSheet<Ruta>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SelectorCandidatas(),
  );
  if (elegida == null || !context.mounted) return;

  await _avisar(
    context,
    ref.read(gestionRutasOficialesProvider).agregar(elegida),
  );
}

class _SelectorCandidatas extends ConsumerWidget {
  const _SelectorCandidatas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidatas = ref.watch(candidatasRutaOficialProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Agregar al mapa',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Flexible(
              child: switch (candidatas) {
                AsyncData(value: final lista) when lista.isEmpty =>
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No hay rutas publicadas para agregar',
                      style: TextStyle(color: AppColors.ink2),
                    ),
                  ),
                AsyncData(value: final lista) => ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ruta in lista)
                      ListTile(
                        key: GestionRutasOficialesScreen.claveCandidata(
                          ruta.id,
                        ),
                        title: Text(ruta.nombre),
                        subtitle: Text(
                          'Por ${ruta.autorNombre} · ${TarjetaRutaExplorar.distanciaYDificultad(ruta)}',
                        ),
                        onTap: () => Navigator.of(context).pop(ruta),
                      ),
                  ],
                ),
                AsyncError() => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'No pudimos cargar las rutas publicadas',
                    style: TextStyle(color: AppColors.ink2),
                  ),
                ),
                _ => const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Pregunta y, si el administrador confirma, saca la ruta del mapa
/// (criterio 5). Cerrar la confirmación sin elegir cuenta como no.
Future<void> _quitar(
  BuildContext context,
  WidgetRef ref,
  RutaOficial oficial,
) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (dialogo) => AlertDialog(
      title: const Text('Quitar del mapa'),
      content: Text(
        '"${oficial.ruta.nombre}" dejará de ser una ruta oficial y las que '
        'van después suben un puesto. La ruta sigue publicada, y quienes ya '
        'la corrieron lo conservan.',
        style: const TextStyle(
          fontSize: 13.5,
          color: AppColors.ink2,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogo).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: GestionRutasOficialesScreen.claveConfirmarQuitar,
          onPressed: () => Navigator.of(dialogo).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Quitar'),
        ),
      ],
    ),
  );
  if (confirmado != true || !context.mounted) return;

  await _avisar(
    context,
    ref.read(gestionRutasOficialesProvider).quitar(oficial),
  );
}
