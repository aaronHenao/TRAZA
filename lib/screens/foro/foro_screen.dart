import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/publicacion_foro.dart';
import '../../services/foro_provider.dart';
import '../../services/reloj_provider.dart';
import '../../services/rutas_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/chip_filtro.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/tarjeta_publicacion.dart';
import '../../widgets/tarjeta_ruta.dart';
import '../rutas/detalle_ruta_screen.dart';
import 'detalle_publicacion_screen.dart';
import 'nueva_publicacion_screen.dart';

/// Las dos caras del foro.
///
/// Las rutas son publicaciones de la comunidad como los temas, pero no se
/// leen igual: un tema se abre para responderlo y una ruta se mira para ir a
/// correrla. Mezcladas en una sola lista, quien busca una ruta tendría que
/// ir descartando conversaciones.
enum SeccionForo {
  temas('Temas'),
  rutas('Rutas');

  const SeccionForo(this.etiqueta);

  final String etiqueta;
}

/// El foro de la comunidad (SCRUM-346): lo que publican los corredores, de lo
/// más reciente a lo más antiguo, con su autor y su fecha.
///
/// Se actualiza en vivo (SCRUM-357). Lo editado y los comentarios cambian en
/// su sitio; las publicaciones nuevas de otros esperan detrás de un aviso
/// para no mover la lista mientras se lee.
class ForoScreen extends ConsumerStatefulWidget {
  const ForoScreen({super.key});

  static const ruta = '/foro';

  static const claveNueva = Key('foro-nueva-publicacion');
  static const claveNuevas = Key('foro-publicaciones-nuevas');

  static Key claveSeccion(SeccionForo seccion) =>
      Key('foro-seccion-${seccion.name}');

  static String textoNuevas(int cuantas) =>
      cuantas == 1 ? '1 publicación nueva' : '$cuantas publicaciones nuevas';

  @override
  ConsumerState<ForoScreen> createState() => _ForoScreenState();
}

class _ForoScreenState extends ConsumerState<ForoScreen> {
  final _desplazamiento = ScrollController();

  SeccionForo _seccion = SeccionForo.temas;

  @override
  void dispose() {
    _desplazamiento.dispose();
    super.dispose();
  }

  /// Muestra lo que llegó en vivo y sube al principio, donde quedó.
  void _verNuevas() {
    ref.read(publicacionesNuevasProvider.notifier).state = const {};
    if (_desplazamiento.hasClients) {
      _desplazamiento.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(foroEnVivoProvider);
    final publicaciones = ref.watch(publicacionesForoProvider);
    final nuevas = ref.watch(publicacionesNuevasProvider);

    // Refrescar a mano también muestra lo que estaba esperando.
    void recargar() {
      ref.read(publicacionesNuevasProvider.notifier).state = const {};
      ref.invalidate(publicacionesForoProvider);
    }

    Future<void> nueva() async {
      // `push`: al volver, el foro se consulta de nuevo y la publicación
      // recién creada aparece arriba (criterio 1 de SCRUM-323).
      await context.push(NuevaPublicacionScreen.ruta);
      recargar();
    }

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Publicar un tema solo se ofrece en los temas: una ruta no
              // se escribe aquí, se publica desde el resumen del
              // entrenamiento que la grabó.
              _Cabecera(onNueva: _seccion == SeccionForo.temas ? nueva : null),
              _Secciones(
                actual: _seccion,
                onCambiar: (seccion) => setState(() => _seccion = seccion),
              ),
              if (_seccion == SeccionForo.rutas)
                const Expanded(child: _Rutas())
              else
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RefreshIndicator(
                          onRefresh: () async => recargar(),
                          child: switch (publicaciones) {
                            AsyncData(value: final lista) when lista.isEmpty =>
                              EstadoVacio(
                                icono: Icons.forum_outlined,
                                titulo: 'Aún no hay publicaciones',
                                detalle:
                                    'Abre la conversación: pregunta o comparte algo '
                                    'sobre running.',
                                accion: OutlinedButton(
                                  onPressed: nueva,
                                  child: const Text('Publicar'),
                                ),
                              ),
                            AsyncData(value: final lista) => _Lista(
                              publicaciones: _sinLasNuevas(lista, nuevas),
                              desplazamiento: _desplazamiento,
                            ),
                            AsyncError() => EstadoVacio(
                              icono: Icons.cloud_off_outlined,
                              titulo: 'No pudimos cargar el foro',
                              detalle:
                                  'Revisa tu conexión e inténtalo de nuevo.',
                              accion: OutlinedButton(
                                onPressed: recargar,
                                child: const Text('Reintentar'),
                              ),
                            ),
                            _ => const Center(
                              child: CircularProgressIndicator(),
                            ),
                          },
                        ),
                      ),
                      if (_cuantasEsperan(publicaciones, nuevas) case final n
                          when n > 0)
                        Positioned(
                          top: AppSpacing.sm,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: _AvisoNuevas(
                              texto: ForoScreen.textoNuevas(n),
                              onVer: _verNuevas,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La lista sin las publicaciones que llegaron en vivo y esperan el aviso.
///
/// Si todo lo que hay es nuevo, se muestra: esconderlo dejaría el foro vacío
/// con un aviso encima.
List<PublicacionForo> _sinLasNuevas(
  List<PublicacionForo> lista,
  Set<String> nuevas,
) {
  if (nuevas.isEmpty) return lista;
  final visibles = lista.where((p) => !nuevas.contains(p.id)).toList();
  return visibles.isEmpty ? lista : visibles;
}

/// Cuántas publicaciones esperan detrás del aviso: las nuevas que ya trajo la
/// consulta y que la lista está escondiendo.
int _cuantasEsperan(
  AsyncValue<List<PublicacionForo>> publicaciones,
  Set<String> nuevas,
) {
  if (publicaciones case AsyncData(value: final lista)) {
    return lista.length - _sinLasNuevas(lista, nuevas).length;
  }
  return 0;
}

/// Pastilla flotante "N publicaciones nuevas · Ver" (SCRUM-357).
class _AvisoNuevas extends StatelessWidget {
  const _AvisoNuevas({required this.texto, required this.onVer});

  final String texto;
  final VoidCallback onVer;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      shape: const StadiumBorder(),
      elevation: 3,
      child: InkWell(
        key: ForoScreen.claveNuevas,
        onTap: onVer,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_upward_rounded,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '$texto · Ver',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
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
  const _Cabecera({required this.onNueva});

  /// Null en el apartado de rutas, donde no hay nada que redactar.
  final VoidCallback? onNueva;

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
                  'Foro',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.19,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Pregunta, comparte y aprende de la comunidad',
                  style: TextStyle(fontSize: 13, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          if (onNueva case final publicar?) ...[
            const SizedBox(width: AppSpacing.sm),
            FilledButton.icon(
              key: ForoScreen.claveNueva,
              onPressed: publicar,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('Publicar'),
            ),
          ],
        ],
      ),
    );
  }
}

/// La tira de chips que elige qué parte del foro se está mirando.
class _Secciones extends StatelessWidget {
  const _Secciones({required this.actual, required this.onCambiar});

  final SeccionForo actual;
  final void Function(SeccionForo seccion) onCambiar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          for (final seccion in SeccionForo.values)
            ChipFiltro(
              key: ForoScreen.claveSeccion(seccion),
              texto: seccion.etiqueta,
              activo: seccion == actual,
              onTap: () => onCambiar(seccion),
            ),
        ],
      ),
    );
  }
}

/// Las rutas que la comunidad ya puede usar (SCRUM-241).
///
/// Cada una dice quién la publicó y cuándo, que es lo que pide el criterio 4,
/// y cuánto mide. Todavía no se abren: el detalle de una ruta es de
/// SCRUM-240.
class _Rutas extends ConsumerWidget {
  const _Rutas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rutas = ref.watch(rutasPublicadasProvider);
    final ahora = ref.read(relojProvider)();

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(rutasPublicadasProvider),
      child: switch (rutas) {
        AsyncData(value: final lista) when lista.isEmpty => const EstadoVacio(
          icono: Icons.route_outlined,
          titulo: 'Todavía no hay rutas publicadas',
          detalle:
              'Cuando termines un entrenamiento, publica su recorrido desde '
              'el resumen para que la comunidad pueda seguirlo.',
        ),
        AsyncData(value: final lista) => ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          itemCount: lista.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, i) => TarjetaRuta(
            key: TarjetaRuta.claveDe(lista[i].id),
            ruta: lista[i],
            ahora: ahora,
            // `push`: al cerrar el detalle se vuelve a la lista donde
            // estaba (SCRUM-240).
            onTap: () => context.push(DetalleRutaScreen.rutaDe(lista[i].id)),
          ),
        ),
        AsyncError() => EstadoVacio(
          icono: Icons.cloud_off_outlined,
          titulo: 'No pudimos cargar las rutas',
          detalle: 'Revisa tu conexión e inténtalo de nuevo.',
          accion: OutlinedButton(
            onPressed: () => ref.invalidate(rutasPublicadasProvider),
            child: const Text('Reintentar'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Lista extends ConsumerWidget {
  const _Lista({required this.publicaciones, required this.desplazamiento});

  final List<PublicacionForo> publicaciones;
  final ScrollController desplazamiento;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ahora = ref.read(relojProvider)();

    return ListView.separated(
      controller: desplazamiento,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: publicaciones.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) {
        final publicacion = publicaciones[i];
        return TarjetaPublicacion(
          key: TarjetaPublicacion.claveDe(publicacion.id),
          publicacion: publicacion,
          ahora: ahora,
          // SCRUM-351: del foro al detalle. Al volver se refresca para que
          // el número de comentarios esté al día.
          onTap: () async {
            await context.push(DetallePublicacionScreen.rutaDe(publicacion.id));
            ref.invalidate(publicacionesForoProvider);
          },
        );
      },
    );
  }
}
