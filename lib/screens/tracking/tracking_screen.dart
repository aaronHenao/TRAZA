import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/estado_cronometro.dart';
import '../../services/cronometro_provider.dart';
import '../../services/distancia_provider.dart';
import '../../services/recorrido_provider.dart';
import '../../theme/traza_theme.dart';
import '../../widgets/controles_entrenamiento.dart';
import '../../widgets/cronometro_entrenamiento.dart';
import '../../widgets/estadisticas_entrenamiento.dart';
import '../../widgets/mapa_entrenamiento.dart';

/// Pantalla del entrenamiento en curso (SCRUM-102).
///
/// Arma el esqueleto de la actividad: mapa, cronómetro, métricas y los
/// botones de pausar y finalizar. De todo eso, esta HU (SCRUM-40) solo
/// implementa la lógica del cronómetro; el resto son huecos listos para
/// que cada HU ponga la suya.
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({
    super.key,
    this.nombreActividad = 'Correr',
    this.mapa,
    this.onFinalizar,
    this.onCancelar,
  });

  /// Tipo de actividad elegido en la pantalla anterior (SCRUM-45).
  final String nombreActividad;

  /// Mapa en vivo, cuando SCRUM-41 lo tenga listo.
  final Widget? mapa;

  /// Se invoca al finalizar, con el tiempo total de la actividad.
  final void Function(Duration duracion)? onFinalizar;

  /// Se invoca al descartar la actividad.
  final VoidCallback? onCancelar;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // La actividad ya se inició: el cronómetro arranca desde cero
    // apenas se monta la pantalla (criterio de aceptación 3).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cronometroProvider.notifier).iniciar();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de segundo plano el tiempo se pone al día de inmediato:
    // el cronómetro cuenta contra el reloj del sistema, no contra los
    // ticks que el sistema haya dejado de entregar.
    if (state == AppLifecycleState.resumed) {
      ref.read(cronometroProvider.notifier).sincronizar();
    }
  }

  void _alternarPausa() {
    ref.read(cronometroProvider.notifier).alternarPausa();
    final pausado = ref.read(cronometroProvider).estaPausado;
    _mostrarAviso(pausado ? 'Actividad en pausa' : 'Actividad reanudada');
  }

  Future<void> _finalizar() async {
    ref.read(cronometroProvider.notifier).detener();
    final estado = ref.read(cronometroProvider);

    // Los puntos se acumularon en local durante la actividad; ahora se
    // envían todos de una vez (SCRUM-110).
    final sincronizado = await ref
        .read(recorridoProvider.notifier)
        .sincronizar();
    if (!mounted) return;

    final onFinalizar = widget.onFinalizar;
    if (onFinalizar != null) {
      onFinalizar(estado.transcurrido);
      return;
    }
    _mostrarAviso(
      sincronizado
          ? 'Entrenamiento finalizado · ${estado.tiempoFormateado}'
          : 'Entrenamiento finalizado · no se pudo guardar el recorrido',
    );
  }

  Future<void> _cancelar() async {
    final descartar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar este entrenamiento?'),
        content: const Text('El progreso no se guardará.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir entrenando'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: TrazaColors.danger),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );

    if (descartar != true || !mounted) return;

    ref.read(cronometroProvider.notifier).reiniciar();
    final onCancelar = widget.onCancelar;
    if (onCancelar != null) {
      onCancelar();
      return;
    }
    final navegador = Navigator.of(context);
    if (navegador.canPop()) navegador.pop();
  }

  void _mostrarAviso(String mensaje) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(mensaje, textAlign: TextAlign.center),
          backgroundColor: TrazaColors.ink,
          behavior: SnackBarBehavior.floating,
          // Por encima de los controles: el aviso no debe tapar los
          // botones de pausar y finalizar.
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 150),
          shape: const StadiumBorder(),
          duration: const Duration(milliseconds: 2400),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene vivo el registro de puntos mientras la pantalla exista,
    // aunque nadie más lo observe (por ejemplo, con un mapa inyectado).
    ref.listen(recorridoProvider, (_, _) {});

    final pausado = ref.watch(
      cronometroProvider.select((estado) => estado.estaPausado),
    );
    // Distancia y ritmo en vivo (SCRUM-112). El ritmo es el de los últimos
    // segundos, no el promedio de toda la actividad (SCRUM-116).
    final distancia = ref.watch(distanciaProvider);

    // Con la actividad en curso no se sale por accidente: el recorrido vive
    // en memoria hasta que se finaliza, así que un atrás sin más lo perdería
    // y dejaría el entrenamiento abierto. Preguntar es además la forma de
    // recordarle al usuario que sigue entrenando (SCRUM-98).
    final enCurso =
        ref.watch(cronometroProvider).marcha != MarchaCronometro.detenido;

    return PopScope(
      canPop: !enCurso,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _cancelar();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(gradient: trazaTrackingGradient),
            child: SafeArea(
              child: Column(
                children: [
                  _BarraSuperior(
                    titulo: widget.nombreActividad,
                    onCerrar: _cancelar,
                  ),
                  MapaEntrenamiento(contenido: widget.mapa),
                  const CronometroEntrenamiento(),
                  EstadisticasEntrenamiento(
                    distancia: distancia.kilometros,
                    ritmo: distancia.ritmoActualFormateado,
                  ),
                  ControlesEntrenamiento(
                    pausado: pausado,
                    onPausar: _alternarPausa,
                    onFinalizar: _finalizar,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarraSuperior extends StatelessWidget {
  const _BarraSuperior({required this.titulo, required this.onCerrar});

  final String titulo;
  final Future<void> Function() onCerrar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Descartar entrenamiento',
            child: Material(
              color: Colors.white.withValues(alpha: 0.1),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onCerrar,
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }
}
