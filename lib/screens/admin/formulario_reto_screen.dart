import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/nuevo_reto.dart';
import '../../models/periodicidad_reto.dart';
import '../../models/vigencia_reto.dart';
import '../../services/reloj_provider.dart';
import '../../services/retos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Formulario de creación de retos (SCRUM-139), con sus validaciones
/// (SCRUM-144).
///
/// El administrador no escribe las fechas: elige la periodicidad y la vigencia
/// se calcula sola (SCRUM-142). Aquí solo se ve.
class FormularioRetoScreen extends ConsumerStatefulWidget {
  const FormularioRetoScreen({super.key});

  static const claveGuardar = Key('reto-guardar');
  static const claveVigencia = Key('reto-vigencia');
  static const claveRecorte = Key('reto-vigencia-recorte');

  @override
  ConsumerState<FormularioRetoScreen> createState() =>
      _FormularioRetoScreenState();
}

class _FormularioRetoScreenState extends ConsumerState<FormularioRetoScreen> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _meta = TextEditingController();
  final _xp = TextEditingController();

  PeriodicidadReto? _periodicidad;

  /// Los errores solo se pintan después del primer intento de guardar. Marcar
  /// en rojo lo que el administrador todavía no ha llegado a escribir sería
  /// regañarlo por adelantado.
  Map<CampoReto, String> _errores = const {};

  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _meta.dispose();
    _xp.dispose();
    super.dispose();
  }

  BorradorReto get _borrador => BorradorReto(
    nombre: _nombre.text,
    descripcion: _descripcion.text,
    periodicidad: _periodicidad,
    meta: _meta.text,
    xp: _xp.text,
  );

  /// Quita el error de un campo en cuanto se toca, para que el rojo no se
  /// quede puesto mientras el administrador ya lo está corrigiendo.
  void _alEditar(CampoReto campo) {
    if (!_errores.containsKey(campo)) return;
    setState(() => _errores = {..._errores}..remove(campo));
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final resultado = await ref.read(creacionRetoProvider).crear(_borrador);
      if (!mounted) return;

      switch (resultado) {
        case RetoCreado():
          // `pop`: la gestión de retos se refresca al recibir el control y el
          // reto recién creado aparece en el catálogo (criterio 1).
          context.pop();
          mostrarToast(context, 'Reto creado y activo');
        case RetoConErrores(:final errores):
          setState(() => _errores = errores);
          mostrarToast(context, 'Revisa los campos marcados');
        case RetoNoGuardado(:final mensaje):
          // Sin tocar lo escrito: se puede reintentar tal cual.
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Nuevo reto', onAtras: context.pop),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: [
                    _Campo(
                      etiqueta: 'Nombre',
                      controlador: _nombre,
                      pista: 'Corre 5 km hoy',
                      error: _errores[CampoReto.nombre],
                      maxCaracteres: maxCaracteresNombreReto,
                      onCambio: () => _alEditar(CampoReto.nombre),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Campo(
                      etiqueta: 'Descripción',
                      controlador: _descripcion,
                      pista:
                          'Qué tiene que hacer el corredor y con qué '
                          'condiciones.',
                      error: _errores[CampoReto.descripcion],
                      lineas: 3,
                      onCambio: () => _alEditar(CampoReto.descripcion),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Periodicidad(
                      elegida: _periodicidad,
                      error: _errores[CampoReto.periodicidad],
                      onElegir: (periodicidad) => setState(() {
                        _periodicidad = periodicidad;
                        _errores = {..._errores}
                          ..remove(CampoReto.periodicidad);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Vigencia(periodicidad: _periodicidad),
                    const SizedBox(height: AppSpacing.md),
                    _MetaYXp(
                      meta: _Campo(
                        etiqueta: 'Meta',
                        controlador: _meta,
                        pista: '5',
                        sufijo: 'km',
                        error: _errores[CampoReto.meta],
                        teclado: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        // La coma se admite porque el teclado del usuario
                        // puede ofrecerla en vez del punto.
                        formatos: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onCambio: () => _alEditar(CampoReto.meta),
                      ),
                      xp: _Campo(
                        etiqueta: 'XP otorgada',
                        controlador: _xp,
                        pista: '50',
                        sufijo: 'XP',
                        error: _errores[CampoReto.xp],
                        teclado: TextInputType.number,
                        formatos: [FilteringTextInputFormatter.digitsOnly],
                        onCambio: () => _alEditar(CampoReto.xp),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _AvisoActivo(),
                  ],
                ),
              ),
              _PieConBoton(
                guardando: _guardando,
                onGuardar: _guardando ? null : _guardar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Meta y XP, lado a lado mientras quepan.
///
/// Con la pantalla muy estrecha —o con el texto del sistema en grande— dos
/// campos numéricos con su etiqueta y su posible mensaje de error no caben en
/// una fila sin quedar ilegibles, así que se apilan.
class _MetaYXp extends StatelessWidget {
  const _MetaYXp({required this.meta, required this.xp});

  final Widget meta;
  final Widget xp;

  /// Por debajo de esto cada columna bajaría de unos 140 px, que no alcanzan
  /// para "XP otorgada" y su mensaje de error.
  static const _anchoMinimo = 300.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        if (restricciones.maxWidth < _anchoMinimo) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              meta,
              const SizedBox(height: AppSpacing.md),
              xp,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: meta),
            const SizedBox(width: 12),
            Expanded(child: xp),
          ],
        );
      },
    );
  }
}

/// Campo de texto con su etiqueta y, cuando lo hay, su mensaje de error
/// debajo (SCRUM-144).
class _Campo extends StatelessWidget {
  const _Campo({
    required this.etiqueta,
    required this.controlador,
    required this.pista,
    required this.onCambio,
    this.error,
    this.sufijo,
    this.lineas = 1,
    this.maxCaracteres,
    this.teclado,
    this.formatos,
  });

  final String etiqueta;
  final TextEditingController controlador;
  final String pista;
  final VoidCallback onCambio;
  final String? error;
  final String? sufijo;
  final int lineas;
  final int? maxCaracteres;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatos;

  @override
  Widget build(BuildContext context) {
    final hayError = error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controlador,
          onChanged: (_) => onCambio(),
          maxLines: lineas,
          maxLength: maxCaracteres,
          keyboardType: teclado,
          inputFormatters: formatos,
          decoration: InputDecoration(
            hintText: pista,
            suffixText: sufijo,
            counterText: '',
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

/// Los tres botones de periodicidad (`.segmented` del prototipo).
class _Periodicidad extends StatelessWidget {
  const _Periodicidad({
    required this.elegida,
    required this.onElegir,
    this.error,
  });

  final PeriodicidadReto? elegida;
  final ValueChanged<PeriodicidadReto> onElegir;
  final String? error;

  static Key claveDe(PeriodicidadReto periodicidad) =>
      Key('periodicidad-${periodicidad.valorDb}');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Periodicidad',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.bgAlt,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: error == null
                ? null
                : Border.all(color: AppColors.danger, width: 1.5),
          ),
          child: Row(
            children: [
              for (final periodicidad in PeriodicidadReto.values)
                Expanded(
                  child: _BotonPeriodicidad(
                    key: claveDe(periodicidad),
                    periodicidad: periodicidad,
                    activa: periodicidad == elegida,
                    onTap: () => onElegir(periodicidad),
                  ),
                ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}

class _BotonPeriodicidad extends StatelessWidget {
  const _BotonPeriodicidad({
    required this.periodicidad,
    required this.activa,
    required this.onTap,
    super.key,
  });

  final PeriodicidadReto periodicidad;
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
          periodicidad.etiqueta,
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

/// La vigencia que le tocará al reto. Es de solo lectura a propósito: la
/// calcula la periodicidad (SCRUM-142) y el administrador no la escribe.
class _Vigencia extends ConsumerWidget {
  const _Vigencia({required this.periodicidad});

  final PeriodicidadReto? periodicidad;

  static const _dias = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  static const _meses = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static String _fecha(DateTime dia) =>
      '${_dias[dia.weekday - 1]} ${dia.day} de ${_meses[dia.month - 1]}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodicidad = this.periodicidad;
    final ahora = ref.read(relojProvider)();

    final (titulo, detalle) = switch (periodicidad) {
      null => (
        'Elige la periodicidad',
        'Se calcula sola: no hay que escribir fechas.',
      ),
      _ => _textoDe(periodicidad, ahora),
    };

    // El período ya venía corriendo: el reto durará menos de lo que sugiere
    // su periodicidad. Se dice antes de guardar, no después.
    final vigencia = periodicidad?.vigenciaDesde(ahora);
    final recorte = vigencia != null && vigencia.empezoAntesDe(ahora)
        ? 'Quedan ${vigencia.diasRestantesDesde(ahora)} de ${vigencia.dias} '
              'días: el período ya empezó.'
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.secondaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 17,
              color: AppColors.secondaryDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VIGENCIA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.44,
                    color: AppColors.ink2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  titulo,
                  key: FormularioRetoScreen.claveVigencia,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
                if (recorte != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 13,
                        color: AppColors.accentInk,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          recorte,
                          key: FormularioRetoScreen.claveRecorte,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentInk,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static (String, String) _textoDe(PeriodicidadReto p, DateTime ahora) {
    final VigenciaReto vigencia = p.vigenciaDesde(ahora);

    return switch (p) {
      PeriodicidadReto.diaria => (
        'Hoy, ${_fecha(vigencia.inicio)}',
        'Termina a medianoche.',
      ),
      PeriodicidadReto.semanal => (
        'Del ${_fecha(vigencia.inicio)} al ${_fecha(vigencia.fin)}',
        'De lunes a domingo.',
      ),
      PeriodicidadReto.mensual => (
        'Del ${_fecha(vigencia.inicio)} al ${_fecha(vigencia.fin)}',
        'Todo el mes en curso.',
      ),
    };
  }
}

/// SCRUM-145: el reto nace activo, y el administrador tiene que saberlo antes
/// de guardar.
class _AvisoActivo extends StatelessWidget {
  const _AvisoActivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondaryTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: AppColors.secondaryDark,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'El reto queda activo apenas lo guardes y aparece en el '
              'catálogo de los corredores.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.secondaryDark,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PieConBoton extends StatelessWidget {
  const _PieConBoton({required this.guardando, required this.onGuardar});

  final bool guardando;
  final VoidCallback? onGuardar;

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
        key: FormularioRetoScreen.claveGuardar,
        onPressed: onGuardar,
        // Ancho completo, como el botón principal del prototipo.
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: guardando
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Crear reto'),
      ),
    );
  }
}
