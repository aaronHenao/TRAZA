import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/resumen_entrenamiento.dart';
import '../../models/revision_ruta.dart';
import '../../models/ruta.dart';
import '../../models/trazado.dart';
import '../../services/rutas_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/traza_theme.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';
import '../../widgets/trazado_recorrido.dart';

/// Formulario para publicar como ruta el recorrido de un entrenamiento
/// finalizado (SCRUM-241).
///
/// Se abre desde el resumen del entrenamiento, que es la pantalla a la que se
/// llega al terminar de correr y también desde el historial: así la acción
/// vive donde el recorrido ya está a la vista, y no hace falta elegirlo de
/// una lista.
class PublicarRutaScreen extends ConsumerStatefulWidget {
  const PublicarRutaScreen({required this.resumen, super.key});

  /// El entrenamiento que se va a publicar. Llega por `extra` desde el
  /// resumen, que ya lo tiene cargado; null si alguien entra escribiendo la
  /// dirección.
  final ResumenEntrenamiento? resumen;

  static const ruta = '/rutas/publicar';

  static const claveNombre = Key('ruta-nombre');
  static const claveDescripcion = Key('ruta-descripcion');
  static const clavePublicar = Key('ruta-publicar');
  static const claveYaPublicada = Key('ruta-ya-publicada');

  static const revisaLosCampos = 'Revisa los campos marcados';

  @override
  ConsumerState<PublicarRutaScreen> createState() => _PublicarRutaScreenState();
}

class _PublicarRutaScreenState extends ConsumerState<PublicarRutaScreen> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();

  /// Los errores solo se pintan después del primer intento de publicar:
  /// marcar en rojo lo que todavía no se ha escrito sería regañar por
  /// adelantado.
  Map<CampoRuta, String> _errores = const {};

  bool _publicando = false;

  /// Si este entrenamiento ya tiene una ruta en pie. Se pregunta al abrir:
  /// mejor decírselo antes de que escriba que después de que toque publicar.
  late final Future<Ruta?> _yaPublicada = _buscarLaQueYaHay();

  Future<Ruta?> _buscarLaQueYaHay() async {
    final id = widget.resumen?.entrenamientoId;
    if (id == null) return null;
    return ref.read(publicacionRutaProvider).rutaDeEntrenamiento(id);
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  /// Quita el error de un campo en cuanto se toca, y repinta el contador.
  void _alEditar(CampoRuta campo) {
    setState(() {
      if (_errores.containsKey(campo)) {
        _errores = {..._errores}..remove(campo);
      }
    });
  }

  Future<void> _publicar(ResumenEntrenamiento resumen) async {
    if (_publicando) return;

    final entrenamientoId = resumen.entrenamientoId;
    if (entrenamientoId == null) {
      mostrarToast(context, PublicacionRuta.sinEntrenamiento);
      return;
    }

    setState(() => _publicando = true);
    try {
      final resultado = await ref
          .read(publicacionRutaProvider)
          .publicar(
            BorradorRuta(
              entrenamientoId: entrenamientoId,
              puntos: resumen.puntos,
              nombre: _nombre.text,
              descripcion: _descripcion.text,
            ),
          );
      if (!mounted) return;

      switch (resultado) {
        case RutaEnRevision():
          context.pop();
          mostrarToast(context, PublicacionRuta.enRevision);
        case RutaConErrores(:final errores):
          setState(() => _errores = errores);
          mostrarToast(context, PublicarRutaScreen.revisaLosCampos);
        case RutaNoPublicada(:final mensaje):
          // Sin tocar lo escrito: se puede reintentar tal cual.
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resumen = widget.resumen;

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Publicar ruta', onAtras: context.pop),
              Expanded(
                child: resumen == null
                    ? const EstadoVacio(
                        icono: Icons.map_outlined,
                        titulo: 'No hay recorrido que publicar',
                        detalle:
                            'Abre un entrenamiento terminado y publica su '
                            'recorrido desde ahí.',
                      )
                    : FutureBuilder<Ruta?>(
                        future: _yaPublicada,
                        builder: (context, estado) {
                          if (estado.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          final ruta = estado.data;
                          if (ruta != null) return _YaPublicada(ruta: ruta);

                          return _Formulario(
                            resumen: resumen,
                            nombre: _nombre,
                            descripcion: _descripcion,
                            errores: _errores,
                            publicando: _publicando,
                            onEditar: _alEditar,
                            onPublicar: () => _publicar(resumen),
                          );
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

/// Lo que se ve cuando ese entrenamiento ya tiene una ruta.
///
/// La barrera de verdad es el índice único de `0031`; esto es para que no se
/// entere después de haber escrito el nombre y la descripción.
class _YaPublicada extends StatelessWidget {
  const _YaPublicada({required this.ruta});

  final Ruta ruta;

  @override
  Widget build(BuildContext context) {
    // Las dos etapas de la revisión (SCRUM-321) siguen sin estar publicadas.
    final enRevision = ruta.estado.pendienteDeRevision;

    return Padding(
      key: PublicarRutaScreen.claveYaPublicada,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            enRevision ? Icons.hourglass_top_rounded : Icons.check_circle,
            size: 42,
            color: enRevision ? AppColors.ink3 : AppColors.secondary,
          ),
          const SizedBox(height: 14),
          Text(
            enRevision
                ? 'Esta ruta está en revisión'
                : 'Ya publicaste esta ruta',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            enRevision
                ? 'La publicaste como "${ruta.nombre}". '
                      '${ruta.estado.etiqueta}: te avisamos cuando se '
                      'publique.'
                : 'La comunidad ya puede ver "${ruta.nombre}".',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.ink2,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: context.pop,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Volver'),
          ),
        ],
      ),
    );
  }
}

/// El trazado que se va a publicar, los dos campos y el aviso de la revisión.
class _Formulario extends StatelessWidget {
  const _Formulario({
    required this.resumen,
    required this.nombre,
    required this.descripcion,
    required this.errores,
    required this.publicando,
    required this.onEditar,
    required this.onPublicar,
  });

  final ResumenEntrenamiento resumen;
  final TextEditingController nombre;
  final TextEditingController descripcion;
  final Map<CampoRuta, String> errores;
  final bool publicando;
  final void Function(CampoRuta campo) onEditar;
  final VoidCallback onPublicar;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: [
              _Recorrido(resumen: resumen, error: errores[CampoRuta.trazado]),
              const SizedBox(height: AppSpacing.md),
              _Campo(
                clave: PublicarRutaScreen.claveNombre,
                etiqueta: 'Nombre',
                controlador: nombre,
                pista: 'Vuelta al Parque Norte',
                error: errores[CampoRuta.nombre],
                maxCaracteres: maxCaracteresNombreRuta,
                onCambio: () => onEditar(CampoRuta.nombre),
              ),
              const SizedBox(height: AppSpacing.md),
              _Campo(
                clave: PublicarRutaScreen.claveDescripcion,
                etiqueta: 'Descripción',
                controlador: descripcion,
                pista:
                    'Cuéntale a la comunidad cómo es: el terreno, las '
                    'subidas, dónde hay sombra.',
                error: errores[CampoRuta.descripcion],
                maxCaracteres: maxCaracteresDescripcionRuta,
                lineas: 6,
                onCambio: () => onEditar(CampoRuta.descripcion),
              ),
              const SizedBox(height: AppSpacing.md),
              const _AvisoRevision(),
            ],
          ),
        ),
        _Pie(publicando: publicando, onPublicar: onPublicar),
      ],
    );
  }
}

/// El trazado del entrenamiento con su distancia.
///
/// Es el mismo dibujo del resumen, para que se reconozca lo que se está
/// publicando. La distancia se enseña aquí porque es la que va a llevar la
/// ruta: la calcula la base a partir de este entrenamiento, no se escribe.
class _Recorrido extends StatelessWidget {
  const _Recorrido({required this.resumen, this.error});

  final ResumenEntrenamiento resumen;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final trazado = Trazado.desdePuntos(resumen.puntos, cortes: resumen.cortes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            height: 160,
            decoration: const BoxDecoration(gradient: trazaTrackingGradient),
            child: trazado.estaVacio
                ? const Center(
                    child: Text(
                      'Este entrenamiento no tiene recorrido',
                      style: TextStyle(fontSize: 12.5, color: Colors.white70),
                    ),
                  )
                : TrazadoRecorrido(trazado: trazado),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(
              Icons.linear_scale_rounded,
              size: 15,
              color: AppColors.ink3,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                resumen.distanciaMetros == null
                    ? 'Este entrenamiento no registró distancia'
                    : '${resumen.distancia} · la distancia que llevará tu ruta',
                style: const TextStyle(fontSize: 12, color: AppColors.ink3),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

/// Que publicar no publica: manda a revisión (criterio 1).
class _AvisoRevision extends StatelessWidget {
  const _AvisoRevision();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_outlined, size: 17, color: AppColors.ink3),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              // SCRUM-321: primero el administrador, después el experto.
              'El administrador y después un Runner Experto revisan tu ruta '
              'antes de que la vea la comunidad. Te avisamos cuando se '
              'publique.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.ink2,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo con su etiqueta, su contador de caracteres y, cuando lo hay, su
/// error debajo.
///
/// El límite no se impone cortando lo que se escribe: si el texto se truncara
/// en silencio, el usuario perdería parte de lo que pegó sin enterarse. Se le
/// deja pasarse y se le dice cuánto sobra, como en el foro.
class _Campo extends StatelessWidget {
  const _Campo({
    required this.clave,
    required this.etiqueta,
    required this.controlador,
    required this.pista,
    required this.maxCaracteres,
    required this.onCambio,
    this.error,
    this.lineas = 1,
  });

  final Key clave;
  final String etiqueta;
  final TextEditingController controlador;
  final String pista;
  final int maxCaracteres;
  final VoidCallback onCambio;
  final String? error;
  final int lineas;

  @override
  Widget build(BuildContext context) {
    final hayError = error != null;
    final usados = controlador.text.trim().length;
    final pasado = usados > maxCaracteres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '$usados/$maxCaracteres',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: pasado ? FontWeight.w700 : FontWeight.w500,
                color: pasado ? AppColors.danger : AppColors.ink3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          key: clave,
          controller: controlador,
          onChanged: (_) => onCambio(),
          minLines: lineas,
          maxLines: lineas == 1 ? 1 : null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: pista,
            filled: hayError,
            fillColor: hayError ? AppColors.dangerTint : null,
            enabledBorder: hayError ? _bordeError : null,
            focusedBorder: hayError ? _bordeError : null,
          ),
        ),
        if (hayError) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  static final _bordeError = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
  );
}

class _Pie extends StatelessWidget {
  const _Pie({required this.publicando, required this.onPublicar});

  final bool publicando;
  final VoidCallback onPublicar;

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
        key: PublicarRutaScreen.clavePublicar,
        onPressed: publicando ? null : onPublicar,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: publicando
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Publicar ruta'),
      ),
    );
  }
}
