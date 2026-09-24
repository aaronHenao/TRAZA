import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/periodicidad_reto.dart';
import '../../models/reto.dart';
import '../../services/retos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/boton_cerrar_sesion.dart';
import '../../widgets/traza_card.dart';

/// Catálogo de retos del administrador (SCRUM-139).
///
/// Es su pantalla de entrada: desde aquí ve lo que los corredores tienen
/// disponible y crea retos nuevos con el botón "+". Editar y retirar llegan
/// con SCRUM-133 y SCRUM-134.
class GestionRetosScreen extends ConsumerWidget {
  const GestionRetosScreen({super.key});

  static const claveBotonNuevo = Key('admin-nuevo-reto');

  static Key claveEstado(EstadoReto estado) => Key('filtro-${estado.valorDb}');

  /// `null` es la opción "Todos", que no filtra nada.
  static Key clavePeriodicidad(PeriodicidadReto? periodicidad) =>
      Key('filtro-${periodicidad?.valorDb ?? 'todas'}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(retosFiltradosProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        key: claveBotonNuevo,
        // `push`: al volver del formulario se regresa aquí, y esta pantalla
        // se refresca para mostrar el reto recién creado.
        onPressed: () async {
          await context.push('/admin/retos/nuevo');
          ref.invalidate(catalogoRetosProvider);
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip: 'Nuevo reto',
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Cabecera(),
              const _Filtros(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => ref.invalidate(catalogoRetosProvider),
                  child: switch (catalogo) {
                    AsyncData(value: final retos) when retos.isEmpty =>
                      const _SinRetos(),
                    AsyncData(value: final retos) => _Lista(retos: retos),
                    AsyncError() => _NoSePudoCargar(
                      onReintentar: () => ref.invalidate(catalogoRetosProvider),
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

class _Cabecera extends StatelessWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gestión de retos',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.19,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Lo que ven los corredores en su sección de retos',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
                SizedBox(height: AppSpacing.sm),
                _EtiquetaRol(),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          // El administrador no tiene pantalla de perfil, así que la salida
          // vive aquí: es su única pantalla.
          BotonCerrarSesion(mensaje: BotonCerrarSesion.mensajeAdministrador),
        ],
      ),
    );
  }
}

class _EtiquetaRol extends StatelessWidget {
  const _EtiquetaRol();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.secondaryTint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 13, color: AppColors.secondaryDark),
          SizedBox(width: 5),
          Text(
            'Administrador',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.secondaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtros del catálogo: por estado y por periodicidad.
class _Filtros extends ConsumerWidget {
  const _Filtros();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(filtroEstadoRetosProvider);
    final periodicidad = ref.watch(filtroPeriodicidadRetosProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.bgAlt,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              children: [
                for (final opcion in EstadoReto.values)
                  Expanded(
                    child: _Pestana(
                      key: GestionRetosScreen.claveEstado(opcion),
                      texto: opcion == EstadoReto.activo
                          ? 'Activos'
                          : 'Retirados',
                      activa: opcion == estado,
                      onTap: () =>
                          ref.read(filtroEstadoRetosProvider.notifier).state =
                              opcion,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          // Wrap y no una fila deslizable: en pantallas estrechas los cuatro
          // no caben, y un chip cortado en el borde no se ve como algo que
          // se pueda arrastrar.
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // null es "todas": no filtra nada.
              for (final opcion in <PeriodicidadReto?>[
                null,
                ...PeriodicidadReto.values,
              ])
                _ChipFiltro(
                  key: GestionRetosScreen.clavePeriodicidad(opcion),
                  texto: opcion?.etiqueta ?? 'Todos',
                  activo: opcion == periodicidad,
                  onTap: () =>
                      ref.read(filtroPeriodicidadRetosProvider.notifier).state =
                          opcion,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    required this.texto,
    required this.activa,
    required this.onTap,
    super.key,
  });

  final String texto;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: activa ? AppColors.bg : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: activa ? AppShadow.card : null,
        ),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: activa ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

class _ChipFiltro extends StatelessWidget {
  const _ChipFiltro({
    required this.texto,
    required this.activo,
    required this.onTap,
    super.key,
  });

  final String texto;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Sin `alignment`: dentro de un Wrap haría que cada chip se estirara
        // a todo el ancho y cayera uno por línea.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: activo ? AppColors.ink : AppColors.bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: activo ? AppColors.ink : AppColors.line),
        ),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: activo ? AppColors.bg : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.retos});

  final List<Reto> retos;

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
      itemCount: retos.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => TarjetaReto(reto: retos[i]),
    );
  }
}

/// Un reto del catálogo, con lo que el administrador necesita reconocerlo.
class TarjetaReto extends StatelessWidget {
  const TarjetaReto({required this.reto, super.key});

  final Reto reto;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconoPeriodicidad(periodicidad: reto.periodicidad),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reto.nombre,
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
                      reto.descripcion,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.ink2,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Insignia(
                texto: '+${reto.xpOtorgada} XP',
                fondo: AppColors.primaryTint,
                color: AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Insignia(texto: reto.periodicidad.etiqueta),
              _Insignia(texto: 'Meta ${_metaTexto(reto.metaKm)} km'),
              _Insignia(
                texto:
                    '${_fecha(reto.vigencia.inicio)} – '
                    '${_fecha(reto.vigencia.fin)}',
              ),
              if (reto.estaActivo)
                const _Insignia(
                  texto: 'Activo',
                  fondo: AppColors.accentTint,
                  color: AppColors.accentInk,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// `5` en vez de `5.0`, pero `2.5` se mantiene.
  static String _metaTexto(double meta) {
    final entero = meta.toInt();
    return meta == entero ? '$entero' : '$meta';
  }

  static const _meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  static String _fecha(DateTime dia) => '${dia.day} ${_meses[dia.month - 1]}';
}

class _IconoPeriodicidad extends StatelessWidget {
  const _IconoPeriodicidad({required this.periodicidad});

  final PeriodicidadReto periodicidad;

  @override
  Widget build(BuildContext context) {
    final (icono, fondo, color) = switch (periodicidad) {
      PeriodicidadReto.diaria => (
        Icons.schedule,
        AppColors.accentTint,
        AppColors.accentInk,
      ),
      PeriodicidadReto.semanal => (
        Icons.bolt_outlined,
        AppColors.primaryTint,
        AppColors.primaryDark,
      ),
      PeriodicidadReto.mensual => (
        Icons.calendar_month_outlined,
        AppColors.secondaryTint,
        AppColors.secondaryDark,
      ),
    };

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icono, size: 22, color: color),
    );
  }
}

class _Insignia extends StatelessWidget {
  const _Insignia({
    required this.texto,
    this.fondo = AppColors.bgAlt,
    this.color = AppColors.ink2,
  });

  final String texto;
  final Color fondo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _SinRetos extends ConsumerWidget {
  const _SinRetos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Vacío por el filtro y vacío de verdad no son lo mismo: si no se
    // distinguen, el administrador cree que perdió sus retos.
    final hayFiltro =
        ref.watch(filtroPeriodicidadRetosProvider) != null ||
        ref.watch(filtroEstadoRetosProvider) != EstadoReto.activo;

    // Sobre un scroll para que "deslizar para refrescar" siga funcionando
    // cuando no hay nada que mostrar.
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 60,
      ),
      children: [
        _Estado(
          icono: hayFiltro ? Icons.filter_alt_outlined : Icons.flag_outlined,
          titulo: hayFiltro
              ? 'Ningún reto con este filtro'
              : 'Aún no hay retos',
          detalle: hayFiltro
              ? 'Prueba con otro estado o periodicidad.'
              : 'Toca el botón + para crear el primero.',
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
          titulo: 'No pudimos cargar los retos',
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
