import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/periodicidad_reto.dart';
import '../../models/reto.dart';
import '../../services/reloj_provider.dart';
import '../../services/retos_provider.dart';
import '../../services/retos_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/chip_filtro.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_reto.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Catálogo de retos del administrador (SCRUM-139).
///
/// Se abre desde el panel del administrador (SCRUM-194): desde aquí ve lo que
/// los corredores tienen disponible y crea retos nuevos con el botón "+".
/// Desde aquí también se edita un reto (SCRUM-148) y se retira del catálogo
/// (SCRUM-161).
class GestionRetosScreen extends ConsumerWidget {
  const GestionRetosScreen({super.key});

  static const ruta = '/admin/retos';
  static const rutaNuevo = '$ruta/nuevo';

  static const claveBotonNuevo = Key('admin-nuevo-reto');

  /// El botón de retirar de una tarjeta, y el de confirmar en su diálogo.
  static Key claveRetirar(Reto reto) => Key('retirar-${reto.id}');
  static const claveConfirmarRetirada = Key('retirar-confirmar');

  static Key claveVista(VistaGestionRetos vista) => Key('vista-${vista.name}');

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
          await context.push(rutaNuevo);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Se llega desde el panel del administrador; si se abrió la ruta
          // directamente no hay a dónde volver.
          if (context.canPop()) ...[
            TrazaIconButton(
              icon: Icons.chevron_left,
              onPressed: context.pop,
              tooltip: 'Volver',
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          const Expanded(
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
              ],
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
    final vista = ref.watch(vistaGestionRetosProvider);
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
                for (final opcion in VistaGestionRetos.values)
                  Expanded(
                    child: _Pestana(
                      key: GestionRetosScreen.claveVista(opcion),
                      texto: opcion.etiqueta,
                      activa: opcion == vista,
                      onTap: () =>
                          ref.read(vistaGestionRetosProvider.notifier).state =
                              opcion,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Chips y no una fila deslizable: en pantallas estrechas los cuatro
        // no caben, y un chip cortado en el borde no se ve como algo que se
        // pueda arrastrar.
        FilaChips(
          children: [
            // null es "todas": no filtra nada.
            for (final opcion in <PeriodicidadReto?>[
              null,
              ...PeriodicidadReto.values,
            ])
              ChipFiltro(
                key: GestionRetosScreen.clavePeriodicidad(opcion),
                texto: opcion?.etiqueta ?? 'Todos',
                activo: opcion == periodicidad,
                onTap: () =>
                    ref.read(filtroPeriodicidadRetosProvider.notifier).state =
                        opcion,
              ),
          ],
        ),
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

class _Lista extends ConsumerWidget {
  const _Lista({required this.retos});

  final List<Reto> retos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El mismo día para toda la lista: si cada tarjeta leyera el reloj por su
    // cuenta, dos podrían decidir distinto al cruzar la medianoche.
    final hoy = ref.read(relojProvider)();

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
      itemBuilder: (context, i) {
        final reto = retos[i];
        return TarjetaRetoAdmin(
          reto: reto,
          hoy: hoy,
          // `push`: al volver, la gestión se refresca y muestra lo editado
          // (SCRUM-152).
          onTap: () =>
              context.push('${GestionRetosScreen.ruta}/editar', extra: reto),
          // Un reto ya retirado no se retira otra vez. Es lo que separa la
          // pestaña de retirados: ahí solo se consulta.
          onRetirar: reto.estaActivo
              ? () => _retirar(context, ref, reto)
              : null,
        );
      },
    );
  }
}

/// Pregunta y, si el administrador confirma, retira el reto (SCRUM-156).
///
/// La confirmación es explícita y dice a quién afecta: retirar no se deshace
/// desde la app, y el administrador no tiene por qué saber de memoria cuánta
/// gente estaba contando con ese reto.
Future<void> _retirar(BuildContext context, WidgetRef ref, Reto reto) async {
  final confirmado = await showDialog<bool>(
    context: context,
    builder: (_) => _ConfirmarRetirada(
      reto: reto,
      // Se pide al abrir el diálogo y no al pintar la lista: son los
      // corredores de un reto, no de los veinte que se ven en pantalla.
      corredores: ref.read(retiradaRetoProvider).comoVanLosCorredores(reto),
    ),
  );
  if (confirmado != true || !context.mounted) return;

  final resultado = await ref.read(retiradaRetoProvider).retirar(reto);
  if (!context.mounted) return;

  switch (resultado) {
    case RetoRetirado():
      // La lista se rehace sola: `retirar` invalida el catálogo.
      mostrarToast(context, 'Reto retirado del catálogo');
    case RetoNoRetirado(:final mensaje):
      mostrarToast(context, mensaje);
  }
}

/// Un reto del catálogo, con lo que el administrador necesita reconocerlo.
class TarjetaRetoAdmin extends StatelessWidget {
  const TarjetaRetoAdmin({
    required this.reto,
    required this.hoy,
    this.onTap,
    this.onRetirar,
    super.key,
  });

  final Reto reto;

  /// Abre el reto para editarlo (SCRUM-148).
  final VoidCallback? onTap;

  /// Lo saca del catálogo. Nulo en los que ya están retirados.
  final VoidCallback? onRetirar;

  /// Desde cuándo se mira la vigencia, para decir si ya caducó.
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconoPeriodicidad(periodicidad: reto.periodicidad),
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
              InsigniaReto(
                texto: '+${reto.xpOtorgada} XP',
                fondo: AppColors.primaryTint,
                color: AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InsigniaReto(texto: reto.periodicidad.etiqueta),
                    InsigniaReto(texto: reto.tipoActividad.nombre),
                    InsigniaReto(
                      texto: 'Meta ${TarjetaReto.textoKm(reto.metaKm)} km',
                    ),
                    InsigniaReto(
                      texto:
                          '${_fecha(reto.vigencia.inicio)} – '
                          '${_fecha(reto.vigencia.fin)}',
                    ),
                    _Situacion(reto: reto, hoy: hoy),
                  ],
                ),
              ),
              // Aquí y no arriba junto a la XP: arriba le robaba ancho al
              // nombre, que es como el administrador reconoce el reto. Y no
              // en un pie propio, que haría cada tarjeta una cuarta parte
              // más alta por una acción que casi nunca se usa. Las
              // insignias dejan sitio libre a su derecha.
              if (onRetirar case final onRetirar?) ...[
                const SizedBox(width: 4),
                IconButton(
                  key: GestionRetosScreen.claveRetirar(reto),
                  onPressed: onRetirar,
                  icon: const Icon(Icons.delete_outline, size: 19),
                  color: AppColors.danger,
                  tooltip: 'Retirar del catálogo',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
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

/// Lo que hay que leer antes de retirar un reto.
class _ConfirmarRetirada extends StatelessWidget {
  const _ConfirmarRetirada({required this.reto, required this.corredores});

  final Reto reto;
  final Future<CorredoresDelReto> corredores;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Retirar este reto?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '«${reto.nombre}» dejará de aparecer en el catálogo de los '
            'corredores. Desde la app no se puede volver a publicar.',
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.ink2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // El diálogo abre al instante y las cuentas llegan después: lo que
          // el administrador tiene que leer no debe esperar a la red.
          FutureBuilder(
            future: corredores,
            builder: (context, estado) => switch (estado.data) {
              final datos? => _AQuienAfecta(corredores: datos),
              null => const Text(
                'Viendo a quién afecta…',
                style: TextStyle(fontSize: 13, color: AppColors.ink3),
              ),
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: GestionRetosScreen.claveConfirmarRetirada,
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Retirar del catálogo'),
        ),
      ],
    );
  }
}

/// Qué le pasa a cada grupo de corredores al retirar el reto (SCRUM-160).
class _AQuienAfecta extends StatelessWidget {
  const _AQuienAfecta({required this.corredores});

  final CorredoresDelReto corredores;

  @override
  Widget build(BuildContext context) {
    final (:enProgreso, :completados, maximoKm: _) = corredores;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (completados > 0)
          _Linea(
            icono: Icons.check_circle_outline,
            color: AppColors.accentInk,
            texto: completados == 1
                ? '1 lo completó: conserva su historial y la XP que ganó.'
                : '$completados lo completaron: conservan su historial y la '
                      'XP que ganaron.',
          ),
        if (enProgreso > 0)
          _Linea(
            icono: Icons.block_outlined,
            color: AppColors.danger,
            texto: enProgreso == 1
                ? '1 lo tiene en progreso: no podrá seguir sumándolo.'
                : '$enProgreso lo tienen en progreso: no podrán seguir '
                      'sumándolo.',
          ),
        if (completados == 0 && enProgreso == 0)
          const _Linea(
            icono: Icons.check_circle_outline,
            color: AppColors.accentInk,
            texto: 'Nadie lo ha activado: no afecta a ningún corredor.',
          ),
      ],
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea({required this.icono, required this.color, required this.texto});

  final IconData icono;
  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// En qué situación está el reto de verdad.
///
/// No basta con `estado`: un reto activo cuya vigencia terminó seguiría
/// diciendo "Activo" dentro de la pestaña de caducados, que es justo lo que
/// confunde.
class _Situacion extends StatelessWidget {
  const _Situacion({required this.reto, required this.hoy});

  final Reto reto;
  final DateTime hoy;

  @override
  Widget build(BuildContext context) {
    final (texto, fondo, color) = switch (reto) {
      _ when !reto.estaActivo => (
        'Retirado',
        AppColors.dangerTint,
        AppColors.danger,
      ),
      _ when reto.vigencia.diasRestantesDesde(hoy) == 0 => (
        'Caducado',
        AppColors.bgAlt,
        AppColors.ink3,
      ),
      _ => ('Vigente', AppColors.accentTint, AppColors.accentInk),
    };

    return InsigniaReto(texto: texto, fondo: fondo, color: color);
  }
}

class _SinRetos extends ConsumerWidget {
  const _SinRetos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(vistaGestionRetosProvider);
    final periodicidad = ref.watch(filtroPeriodicidadRetosProvider);

    // Cada combinación dice qué falta: un mensaje común obliga a mirar qué
    // pestaña y qué chip están activos para entenderlo.
    final (titulo, detalle) = switch ((vista, periodicidad)) {
      (VistaGestionRetos.vigentes, null) => (
        'No hay retos vigentes',
        'Toca el botón + para publicar uno.',
      ),
      (VistaGestionRetos.caducados, null) => (
        'Ningún reto ha caducado',
        'Aquí aparecerán los que pasen su fecha de fin.',
      ),
      (VistaGestionRetos.retirados, null) => (
        'No has retirado ningún reto',
        'Los que retires del catálogo aparecerán aquí.',
      ),
      (_, final p) => (
        'Ningún reto ${p!.etiqueta.toLowerCase()} en ${vista.etiqueta.toLowerCase()}',
        'Prueba con otra periodicidad o con otra pestaña.',
      ),
    };

    return EstadoVacio(
      icono: periodicidad == null
          ? vista.iconoVacio
          : Icons.filter_alt_outlined,
      titulo: titulo,
      detalle: detalle,
    );
  }
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
