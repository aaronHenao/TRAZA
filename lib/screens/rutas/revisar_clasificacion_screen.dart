import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/dificultad.dart';
import '../../models/punto_gps.dart';
import '../../models/ruta.dart';
import '../../services/reloj_provider.dart';
import '../../services/revision_clasificacion_provider.dart';
import '../../services/rutas_provider.dart';
import '../../services/rutas_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/traza_theme.dart';
import '../../utils/fecha_relativa.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/mapa_trayecto.dart';
import '../../widgets/tarjeta_reto.dart' show TarjetaReto;
import '../../widgets/tarjeta_ruta.dart';
import '../../widgets/tarjeta_ruta_explorar.dart';
import '../../widgets/traza_card.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Donde el Runner Experto revisa la clasificación de una ruta (SCRUM-261,
/// HU-35).
///
/// Enseña la ruta —por dónde va, cómo se llama y de quién es—, la
/// dificultad propuesta y los datos en que se basa: la distancia y el
/// desnivel acumulado (criterio 2). Al final deja confirmarla (SCRUM-262,
/// criterio 3); corregirla viene en la subtarea que sigue.
///
/// Solo la ve quien la base dice que puede (`puede_revisar_clasificacion`,
/// 0042, criterio 1): un Runner Experto que no sea el autor. A los demás se
/// les dice por qué no, en vez de enseñarles algo que no podrían usar.
class RevisarClasificacionScreen extends ConsumerWidget {
  const RevisarClasificacionScreen({required this.rutaId, super.key});

  final String rutaId;

  static String rutaDe(String rutaId) =>
      '/rutas/${Uri.encodeComponent(rutaId)}/revisar';

  static const titulo = 'Revisar clasificación';

  /// El botón del detalle de la ruta que abre esta pantalla.
  static const claveAbrir = Key('revisar-clasificacion-abrir');
  static const claveDificultad = Key('revisar-clasificacion-dificultad');
  static const claveDistancia = Key('revisar-clasificacion-distancia');
  static const claveDesnivel = Key('revisar-clasificacion-desnivel');
  static const claveSinPermiso = Key('revisar-clasificacion-sin-permiso');
  static const claveNoDisponible = Key('revisar-clasificacion-no-disponible');
  static const claveError = Key('revisar-clasificacion-error');
  static const claveReintentar = Key('revisar-clasificacion-reintentar');
  static const claveConfirmar = Key('revisar-clasificacion-confirmar');

  static const rotuloDificultad = 'DIFICULTAD PROPUESTA';
  static const rotuloDatos = 'EN QUÉ SE BASA';

  static const conPropuesta = 'Es la que tiene la ruta ahora.';
  static const sinPropuesta = 'Todavía no tiene una dificultad propuesta.';
  static const distanciaTotal = 'Distancia total de la ruta';
  static const sinDistanciaDetalle =
      'Esta ruta se guardó sin su distancia, así que no se puede saber '
      'cuánto mide.';
  static const desnivelNoDisponible =
      'La app no guarda la altitud del recorrido, así que el desnivel '
      'todavía no se puede calcular.';

  /// El botón de confirmar dice qué se confirma (SCRUM-262): queda lejos
  /// de la dificultad, debajo de los datos.
  static String confirmarComo(Dificultad dificultad) =>
      'Confirmar como ${dificultad.etiqueta.toLowerCase()}';
  static String confirmada(Dificultad dificultad) =>
      'Confirmaste la ruta como ${dificultad.etiqueta.toLowerCase()}.';
  static const yaNoPuedes = 'Ya no puedes revisar esta ruta.';
  static const noSeConfirmo =
      'No pudimos confirmar la dificultad. Inténtalo de nuevo.';

  static const sinPermisoTitulo = 'No puedes revisar esta clasificación';
  static const sinPermisoDetalle =
      'Las clasificaciones las revisa un Runner Experto, y nunca las de sus '
      'propias rutas.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ruta = ref.watch(rutaProvider(rutaId));
    final puede = ref.watch(puedeRevisarClasificacionProvider(rutaId));

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: titulo, onAtras: context.pop),
              Expanded(child: _cuerpo(ref, ruta, puede)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cuerpo(
    WidgetRef ref,
    AsyncValue<Ruta?> ruta,
    AsyncValue<bool> puede,
  ) {
    // Reintentando tras un error se ve que está cargando, no el error de
    // antes.
    final fallo =
        (ruta.hasError && !ruta.isLoading) ||
        (puede.hasError && !puede.isLoading);
    if (fallo) {
      return EstadoVacio(
        key: claveError,
        icono: Icons.cloud_off_rounded,
        titulo: 'No pudimos cargar la ruta',
        detalle: 'Revisa tu conexión e inténtalo de nuevo.',
        accion: OutlinedButton(
          key: claveReintentar,
          onPressed: () => ref
            ..invalidate(rutaProvider(rutaId))
            ..invalidate(puedeRevisarClasificacionProvider(rutaId)),
          child: const Text('Reintentar'),
        ),
      );
    }
    if (!ruta.hasValue || !puede.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    // Primero si la ruta sigue ahí: de una que ya no existe, la base también
    // contesta que no se puede revisar, y decir "no puedes" sería engañar.
    final encontrada = ruta.requireValue;
    if (encontrada == null) {
      return const EstadoVacio(
        key: claveNoDisponible,
        icono: Icons.explore_off_outlined,
        titulo: 'Esta ruta ya no está disponible',
        detalle: 'Puede que su autor la haya retirado.',
      );
    }

    // A quien no puede revisarla no se le enseña la revisión.
    if (!puede.requireValue) {
      return const EstadoVacio(
        key: claveSinPermiso,
        icono: Icons.lock_outline_rounded,
        titulo: sinPermisoTitulo,
        detalle: sinPermisoDetalle,
      );
    }

    return _Contenido(ruta: encontrada, ahora: ref.read(relojProvider)());
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.ruta, required this.ahora});

  final Ruta ruta;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final fecha = ruta.fechaPublicacion ?? ruta.fechaCreacion;
    final dificultad = ruta.dificultad;

    return Column(
      children: [
        Expanded(child: _datos(fecha)),
        // Sin dificultad propuesta no hay nada que confirmar.
        if (dificultad != null)
          _Confirmar(rutaId: ruta.id, dificultad: dificultad),
      ],
    );
  }

  Widget _datos(DateTime fecha) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        _Mapa(trazado: ruta.trazado),
        const SizedBox(height: AppSpacing.md),
        Text(
          ruta.nombre,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.19,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Por ${ruta.autorNombre} · ${fechaRelativa(fecha, ahora)}',
          style: const TextStyle(fontSize: 13, color: AppColors.ink2),
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Rotulo(RevisarClasificacionScreen.rotuloDificultad),
        const SizedBox(height: AppSpacing.sm),
        _DificultadPropuesta(dificultad: ruta.dificultad),
        const SizedBox(height: AppSpacing.lg),
        const _Rotulo(RevisarClasificacionScreen.rotuloDatos),
        const SizedBox(height: AppSpacing.sm),
        _Distancia(km: ruta.distanciaKm),
        const SizedBox(height: AppSpacing.sm),
        const _Dato(
          key: RevisarClasificacionScreen.claveDesnivel,
          icono: Icons.terrain_rounded,
          valor: TarjetaRutaExplorar.sinDesnivel,
          detalle: RevisarClasificacionScreen.desnivelNoDisponible,
          conValor: false,
        ),
      ],
    );
  }
}

/// Confirmar la dificultad propuesta (SCRUM-262, criterio 3 de HU-35): la
/// ruta queda revisada y su dificultad, a la vista de todos.
///
/// Va fijo al pie, como el botón de publicar una ruta: siempre a mano,
/// aunque los datos no quepan en la pantalla, y los avisos suben para no
/// taparlo. Mientras se guarda no se puede volver a tocar, para que un doble
/// toque no mande dos confirmaciones. Si sale bien, avisa y vuelve al detalle
/// de la ruta, ya al día; si no, lo dice y deja intentarlo otra vez.
class _Confirmar extends ConsumerStatefulWidget {
  const _Confirmar({required this.rutaId, required this.dificultad});

  final String rutaId;
  final Dificultad dificultad;

  @override
  ConsumerState<_Confirmar> createState() => _ConfirmarState();
}

class _ConfirmarState extends ConsumerState<_Confirmar> {
  var _guardando = false;

  Future<void> _confirmar() async {
    setState(() => _guardando = true);
    try {
      await ref
          .read(rutasRepositoryProvider)
          .confirmarClasificacion(widget.rutaId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarToast(
        context,
        error is SinPermisoParaRevisarException
            ? RevisarClasificacionScreen.yaNoPuedes
            : RevisarClasificacionScreen.noSeConfirmo,
        // Por encima del pie: si no, taparía el botón para reintentar.
        separacionInferior: 90,
      );
      return;
    }
    if (!mounted) return;

    // La ruta cambió: el detalle y su botón de revisar la vuelven a pedir.
    ref
      ..invalidate(rutaProvider(widget.rutaId))
      ..invalidate(puedeRevisarClasificacionProvider(widget.rutaId));
    mostrarToast(
      context,
      RevisarClasificacionScreen.confirmada(widget.dificultad),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        12,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: FilledButton(
        key: RevisarClasificacionScreen.claveConfirmar,
        onPressed: _guardando ? null : _confirmar,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: _guardando
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                  semanticsLabel: 'Guardando',
                ),
              )
            : Text(RevisarClasificacionScreen.confirmarComo(widget.dificultad)),
      ),
    );
  }
}

/// La dificultad que trae la ruta, que es lo que el experto revisa. Sin
/// ella, la ruta va "Sin clasificar", como en su tarjeta.
class _DificultadPropuesta extends StatelessWidget {
  const _DificultadPropuesta({required this.dificultad});

  final Dificultad? dificultad;

  @override
  Widget build(BuildContext context) {
    final dificultad = this.dificultad;

    return _Dato(
      key: RevisarClasificacionScreen.claveDificultad,
      icono: Icons.signal_cellular_alt_rounded,
      valor: dificultad?.etiqueta ?? TarjetaRutaExplorar.sinDificultad,
      detalle: dificultad == null
          ? RevisarClasificacionScreen.sinPropuesta
          : RevisarClasificacionScreen.conPropuesta,
      conValor: dificultad != null,
    );
  }
}

/// Cuánto mide la ruta, como en su detalle.
class _Distancia extends StatelessWidget {
  const _Distancia({required this.km});

  final double? km;

  @override
  Widget build(BuildContext context) {
    final km = this.km;

    return _Dato(
      key: RevisarClasificacionScreen.claveDistancia,
      icono: Icons.linear_scale_rounded,
      valor: km == null
          ? TarjetaRuta.sinDistancia
          // Los km se escriben igual en toda la app.
          : '${TarjetaReto.textoKm(km)} km',
      detalle: km == null
          ? RevisarClasificacionScreen.sinDistanciaDetalle
          : RevisarClasificacionScreen.distanciaTotal,
      conValor: km != null,
    );
  }
}

/// Un dato en su tarjeta: el valor grande y, debajo, qué es o por qué falta.
///
/// Se lee de una vez con el lector de pantalla: el valor sin lo que es no
/// se entiende.
class _Dato extends StatelessWidget {
  const _Dato({
    required this.icono,
    required this.valor,
    required this.detalle,
    required this.conValor,
    super.key,
  });

  final IconData icono;
  final String valor;
  final String detalle;

  /// Sin valor, se dice más bajo: es la falta del dato, no el dato.
  final bool conValor;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: TrazaCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.secondaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, size: 20, color: AppColors.secondaryDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: TextStyle(
                      fontSize: conValor ? 19 : 14,
                      fontWeight: FontWeight.w800,
                      color: conValor ? AppColors.ink : AppColors.ink2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.66,
        color: AppColors.ink2,
      ),
    );
  }
}

/// El trazado sobre el mapa, como en el detalle de la ruta.
class _Mapa extends StatelessWidget {
  const _Mapa({required this.trazado});

  final List<PuntoRuta> trazado;

  /// Los puntos como los pide el mapa, que está hecho para el recorrido de un
  /// entrenamiento. El instante no se usa para dibujar, así que va uno
  /// cualquiera.
  static List<PuntoGps> _paraElMapa(List<PuntoRuta> trazado) => [
    for (final punto in trazado)
      PuntoGps(
        latitud: punto.latitud,
        longitud: punto.longitud,
        capturadoEn: _sinHora,
      ),
  ];

  static final _sinHora = DateTime.utc(2000);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 200,
        child: trazado.isEmpty
            ? const DecoratedBox(
                decoration: BoxDecoration(gradient: trazaTrackingGradient),
                child: Center(
                  child: Text(
                    'Esta ruta no guardó su trazado',
                    style: TextStyle(fontSize: 12.5, color: Colors.white70),
                  ),
                ),
              )
            : MapaTrayecto(puntos: _paraElMapa(trazado)),
      ),
    );
  }
}
