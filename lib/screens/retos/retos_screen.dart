import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/periodicidad_reto.dart';
import '../../services/reloj_provider.dart';
import '../../services/retos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/chip_filtro.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/fila_reto_usuario.dart';
import '../../widgets/tarjeta_reto.dart';
import '../../widgets/traza_top_bar.dart';

/// Los retos del corredor (SCRUM-164): los que tiene en juego y los que
/// puede activar (SCRUM-170).
///
/// Lo activo va arriba porque es lo que más se consulta —cuánto falta para la
/// meta—, mientras que activar un reto se hace de vez en cuando. Lo que ya se
/// completó o venció sale de aquí y queda en el historial, bajo el reloj:
/// arriba está solo lo que sigue en juego.
class RetosScreen extends ConsumerWidget {
  const RetosScreen({super.key});

  static const claveHistorial = Key('retos-historial');

  /// `null` es la pestaña "Todos", que no filtra nada.
  static Key clavePestana(PeriodicidadReto? periodicidad) =>
      Key('reto-tab-${periodicidad?.valorDb ?? 'todas'}');

  static const claveEnCurso = Key('retos-en-curso');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(retosCorredorProvider);

    void recargar() {
      ref.invalidate(retosVigentesProvider);
      ref.invalidate(misRetosProvider);
    }

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Cabecera(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => recargar(),
                  child: switch (vista) {
                    AsyncData(value: final datos) => _Contenido(datos: datos),
                    AsyncError() => _NoSePudoCargar(onReintentar: recargar),
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

/// Las dos secciones, una debajo de la otra en el mismo scroll.
class _Contenido extends ConsumerWidget {
  const _Contenido({required this.datos});

  final VistaRetosCorredor datos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodicidad = ref.watch(filtroRetosCorredorProvider);
    final disponibles = periodicidad == null
        ? datos.disponibles
        : datos.disponibles
              .where((reto) => reto.periodicidad == periodicidad)
              .toList();

    // Sin nada activo y sin catálogo, la pantalla entera está vacía: el
    // mensaje se centra en vez de colgar de un encabezado que no viene a
    // cuento.
    if (datos.enCurso.isEmpty && datos.disponibles.isEmpty) {
      return const _SinRetos(hayFiltro: false);
    }

    // El mismo día para toda la pantalla: si cada tarjeta leyera el reloj por
    // su cuenta, dos podrían contar días distintos al cruzar la medianoche.
    final hoy = ref.read(relojProvider)();
    final hayEnCurso = datos.enCurso.isNotEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        if (hayEnCurso) ...[
          const _TituloSeccion('EN CURSO', key: RetosScreen.claveEnCurso),
          for (final mio in datos.enCurso)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: FilaRetoUsuario(
                key: FilaRetoUsuario.claveDe(mio.reto.id),
                reto: mio,
                ahora: hoy,
                onTap: () =>
                    context.push('/retos/${mio.reto.id}', extra: mio.reto),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          // El encabezado solo hace falta cuando hay algo encima de lo que
          // distinguirlo: sin retos en curso, el título de la pantalla ya
          // dice que esto son retos.
          const _TituloSeccion('DISPONIBLES'),
        ],
        const _Pestanas(),
        if (disponibles.isEmpty)
          _SinDisponibles(hayFiltro: periodicidad != null)
        else
          for (final reto in disponibles)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: TarjetaReto(
                key: TarjetaReto.claveDe(reto.id),
                reto: reto,
                hoy: hoy,
                // SCRUM-166: del listado al detalle.
                onTap: () => context.push('/retos/${reto.id}', extra: reto),
              ),
            ),
      ],
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: AppColors.ink3,
        ),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Retos',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.19,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Elige uno y gana XP al cumplirlo',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Historial de retos, como el botón de la topbar del prototipo.
          TrazaIconButton(
            key: RetosScreen.claveHistorial,
            icon: Icons.schedule,
            tooltip: 'Mis retos',
            onPressed: () => context.push('/retos/historial'),
          ),
        ],
      ),
    );
  }
}

/// Diario · Semanal · Mensual, como el `.segmented` del prototipo, más
/// "Todos" para no esconder nada por defecto.
class _Pestanas extends ConsumerWidget {
  const _Pestanas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elegida = ref.watch(filtroRetosCorredorProvider);

    return FilaChips(
      children: [
        for (final opcion in <PeriodicidadReto?>[
          null,
          ...PeriodicidadReto.values,
        ])
          ChipFiltro(
            key: RetosScreen.clavePestana(opcion),
            texto: opcion?.etiqueta ?? 'Todos',
            activo: opcion == elegida,
            onTap: () =>
                ref.read(filtroRetosCorredorProvider.notifier).state = opcion,
          ),
      ],
    );
  }
}

/// El hueco de "Disponibles" cuando hay retos en curso arriba.
///
/// Va sin centrar y sin scroll propio: es una sección de una lista, no la
/// pantalla entera.
class _SinDisponibles extends ConsumerWidget {
  const _SinDisponibles({required this.hayFiltro});

  final bool hayFiltro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodicidad = ref.watch(filtroRetosCorredorProvider);

    return MensajeVacio(
      icono: hayFiltro ? Icons.filter_alt_outlined : Icons.flag_outlined,
      titulo: hayFiltro
          ? 'Ningún reto ${periodicidad!.etiqueta.toLowerCase()}'
          : 'Nada más por ahora',
      detalle: hayFiltro
          ? _SinRetos.detalleDe(periodicidad!)
          : 'Ya activaste todos los retos vigentes. Vuelve más tarde.',
    );
  }
}

class _SinRetos extends ConsumerWidget {
  const _SinRetos({required this.hayFiltro});

  final bool hayFiltro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hayFiltro) {
      return const EstadoVacio(
        icono: Icons.flag_outlined,
        titulo: 'No hay retos disponibles',
        detalle: 'Vuelve más tarde: aquí aparecerán los retos vigentes.',
      );
    }

    // Se nombra la periodicidad: un mensaje común obliga a mirar qué chip
    // está activo para saber de qué habla.
    final periodicidad = ref.watch(filtroRetosCorredorProvider)!;

    return EstadoVacio(
      icono: Icons.filter_alt_outlined,
      titulo: 'Ningún reto ${periodicidad.etiqueta.toLowerCase()}',
      detalle: detalleDe(periodicidad),
    );
  }

  static String detalleDe(PeriodicidadReto periodicidad) =>
      switch (periodicidad) {
        PeriodicidadReto.diaria =>
          'Hoy no hay ninguno. Prueba con los semanales o mensuales.',
        PeriodicidadReto.semanal =>
          'Esta semana no hay ninguno. Prueba con los diarios o mensuales.',
        PeriodicidadReto.mensual =>
          'Este mes no hay ninguno. Prueba con los diarios o semanales.',
      };
}

class _NoSePudoCargar extends StatelessWidget {
  const _NoSePudoCargar({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return EstadoVacio(
      icono: Icons.cloud_off_outlined,
      titulo: 'No pudimos cargar los retos',
      detalle: 'Revisa tu conexión e inténtalo de nuevo.',
      accion: OutlinedButton(
        onPressed: onReintentar,
        child: const Text('Reintentar'),
      ),
    );
  }
}
