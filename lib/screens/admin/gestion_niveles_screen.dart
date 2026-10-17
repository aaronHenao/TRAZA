import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/nivel.dart';
import '../../services/niveles_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_top_bar.dart';

/// Gestión de niveles del administrador (SCRUM-182).
///
/// Muestra la progresión completa ordenada por umbral, de menor a mayor
/// (criterio 1 de SCRUM-177), y desde aquí se crean niveles nuevos con el
/// botón "+".
class GestionNivelesScreen extends ConsumerWidget {
  const GestionNivelesScreen({super.key});

  static const ruta = '/admin/niveles';
  static const rutaNuevo = '$ruta/nuevo';

  static const claveBotonNuevo = Key('admin-nuevo-nivel');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(catalogoNivelesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: claveBotonNuevo,
        // `push`: al volver del formulario se regresa aquí, y el listado se
        // refresca para mostrar el nivel recién creado.
        onPressed: () async {
          await context.push(rutaNuevo);
          ref.invalidate(catalogoNivelesProvider);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Nuevo nivel',
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrazaTopBar(
                titulo: 'Gestión de niveles',
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
                  'La progresión que van subiendo los corredores con su '
                  'experiencia',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(catalogoNivelesProvider),
                  child: switch (catalogo) {
                    AsyncData(value: final niveles) when niveles.isEmpty =>
                      const _SinNiveles(),
                    AsyncData(value: final niveles) => _Lista(niveles: niveles),
                    AsyncError() => _NoSePudoCargar(
                      onReintentar: () =>
                          ref.invalidate(catalogoNivelesProvider),
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

class _Lista extends StatelessWidget {
  const _Lista({required this.niveles});

  final List<Nivel> niveles;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        // Hueco para que el "+" no tape la última tarjeta.
        96,
      ),
      itemCount: niveles.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => TarjetaNivel(
        nivel: niveles[i],
        posicion: i + 1,
        // El listado viene ordenado, así que el siguiente nivel es el de al
        // lado: con él se sabe dónde termina el tramo de este.
        siguiente: i + 1 < niveles.length ? niveles[i + 1] : null,
      ),
    );
  }
}

/// Un nivel de la progresión, con el tramo de experiencia que ocupa.
class TarjetaNivel extends StatelessWidget {
  const TarjetaNivel({
    required this.nivel,
    required this.posicion,
    this.siguiente,
    super.key,
  });

  final Nivel nivel;

  /// Qué puesto ocupa en la progresión: 1 es el primero que se alcanza.
  final int posicion;

  /// El nivel que viene después, o null si este es el más alto.
  final Nivel? siguiente;

  /// Hasta dónde llega este nivel.
  ///
  /// El tramo termina justo antes del umbral del siguiente: con Bronce en 100
  /// y Plata en 500, Bronce llega hasta 499. El último no tiene final.
  String get alcance => siguiente == null
      ? 'Nivel más alto'
      : 'Hasta ${siguiente!.umbralExperiencia - 1} XP';

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Row(
        children: [
          _Posicion(posicion: posicion),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nivel.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alcance,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // El umbral con el que se entra al nivel: el dato que lo define.
          _Insignia(texto: '${nivel.umbralExperiencia} XP'),
        ],
      ),
    );
  }
}

/// El puesto del nivel en la progresión.
class _Posicion extends StatelessWidget {
  const _Posicion({required this.posicion});

  final int posicion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.secondaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$posicion',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.secondaryDark,
        ),
      ),
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }
}

class _SinNiveles extends StatelessWidget {
  const _SinNiveles();

  @override
  Widget build(BuildContext context) {
    // Sobre un scroll para que "deslizar para refrescar" siga funcionando
    // cuando no hay nada que mostrar.
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 60,
      ),
      children: const [
        _Estado(
          icono: Icons.stairs_outlined,
          titulo: 'Aún no hay niveles',
          detalle: 'Toca el botón + para crear el primero.',
        ),
      ],
    );
  }
}

class _NoSePudoCargar extends StatelessWidget {
  const _NoSePudoCargar({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 80,
      ),
      children: [
        _Estado(
          icono: Icons.cloud_off_outlined,
          titulo: 'No pudimos cargar los niveles',
          detalle: 'Revisa tu conexión e inténtalo de nuevo.',
          accion: OutlinedButton(
            onPressed: onReintentar,
            child: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.bgAlt,
          ),
          child: Icon(icono, size: 30, color: AppColors.ink3),
        ),
        const SizedBox(height: 12),
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          detalle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: AppColors.ink2),
        ),
        if (accion != null) ...[const SizedBox(height: AppSpacing.md), accion!],
      ],
    );
  }
}
