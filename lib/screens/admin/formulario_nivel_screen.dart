import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/nivel.dart';
import '../../models/nuevo_nivel.dart';
import '../../services/niveles_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Formulario de creación de niveles (SCRUM-182), con sus validaciones
/// (SCRUM-181).
class FormularioNivelScreen extends ConsumerStatefulWidget {
  const FormularioNivelScreen({super.key});

  static const claveGuardar = Key('nivel-guardar');

  @override
  ConsumerState<FormularioNivelScreen> createState() =>
      _FormularioNivelScreenState();
}

class _FormularioNivelScreenState extends ConsumerState<FormularioNivelScreen> {
  final _nombre = TextEditingController();
  final _umbral = TextEditingController();

  /// Los errores solo se pintan después del primer intento de guardar. Marcar
  /// en rojo lo que el administrador todavía no ha llegado a escribir sería
  /// regañarlo por adelantado.
  Map<CampoNivel, String> _errores = const {};

  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _umbral.dispose();
    super.dispose();
  }

  BorradorNivel get _borrador =>
      BorradorNivel(nombre: _nombre.text, umbral: _umbral.text);

  /// Los niveles con los que se compara para no repetir nombre ni umbral.
  ///
  /// Si el listado no se pudo cargar, se valida contra una lista vacía: la
  /// base sigue teniendo la última palabra y su rechazo marca el campo igual.
  List<Nivel> get _existentes =>
      ref.read(catalogoNivelesProvider).valueOrNull ?? const [];

  /// Quita el error de un campo en cuanto se toca, para que el rojo no se
  /// quede puesto mientras el administrador ya lo está corrigiendo.
  void _alEditar(CampoNivel campo) {
    if (!_errores.containsKey(campo)) return;
    setState(() => _errores = {..._errores}..remove(campo));
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final resultado = await ref
          .read(creacionNivelProvider)
          .crear(_borrador, _existentes);
      if (!mounted) return;

      switch (resultado) {
        case NivelCreado():
          // `pop`: la gestión se refresca al recibir el control y el nivel
          // recién creado aparece en el listado (criterio 1).
          context.pop();
          mostrarToast(context, 'Nivel creado');
        case NivelConErrores(:final errores):
          setState(() => _errores = errores);
          mostrarToast(context, 'Revisa los campos marcados');
        case NivelNoGuardado(:final mensaje):
          // Sin tocar lo escrito: se puede reintentar tal cual.
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existentes = ref.watch(catalogoNivelesProvider).valueOrNull;
    final masAlto = existentes == null || existentes.isEmpty
        ? null
        : existentes.last;

    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(titulo: 'Nuevo nivel', onAtras: context.pop),
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
                      pista: 'Bronce',
                      error: _errores[CampoNivel.nombre],
                      maxCaracteres: maxCaracteresNombreNivel,
                      onCambio: () => _alEditar(CampoNivel.nombre),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Campo(
                      etiqueta: 'Umbral de experiencia',
                      controlador: _umbral,
                      pista: '100',
                      sufijo: 'XP',
                      error: _errores[CampoNivel.umbral],
                      teclado: TextInputType.number,
                      // Solo dígitos: la experiencia se acumula entera y el
                      // signo menos no tiene sentido en un umbral.
                      formatos: [FilteringTextInputFormatter.digitsOnly],
                      ayuda: masAlto == null
                          ? 'La experiencia con la que el corredor entra a '
                                'este nivel.'
                          : 'El nivel más alto ahora empieza en '
                                '${masAlto.umbralExperiencia} XP.',
                      onCambio: () => _alEditar(CampoNivel.umbral),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _AvisoProgresion(),
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

/// Campo de texto con su etiqueta y, cuando lo hay, su mensaje de error
/// debajo (SCRUM-181).
class _Campo extends StatelessWidget {
  const _Campo({
    required this.etiqueta,
    required this.controlador,
    required this.pista,
    required this.onCambio,
    this.error,
    this.sufijo,
    this.ayuda,
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

  /// Texto de apoyo bajo el campo. Se oculta mientras haya error, para no
  /// competir con él.
  final String? ayuda;
  final int? maxCaracteres;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatos;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    final hayError = error != null;
    final ayuda = this.ayuda;

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
            error,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ] else if (ayuda != null) ...[
          const SizedBox(height: 6),
          Text(
            ayuda,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.ink2,
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

/// Explica qué significa el umbral dentro de la progresión, para que quede
/// claro que cada nivel va hasta donde empieza el siguiente.
class _AvisoProgresion extends StatelessWidget {
  const _AvisoProgresion();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondaryTint,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.stairs_outlined, size: 18, color: AppColors.secondaryDark),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cada nivel va desde su umbral hasta el del siguiente, así que '
              'dos niveles no pueden empezar en la misma experiencia.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.secondaryDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El botón de guardar, fijo al pie para que no haya que bajar a buscarlo.
class _PieConBoton extends StatelessWidget {
  const _PieConBoton({required this.guardando, required this.onGuardar});

  final bool guardando;
  final VoidCallback? onGuardar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: FormularioNivelScreen.claveGuardar,
          onPressed: onGuardar,
          child: guardando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Crear nivel'),
        ),
      ),
    );
  }
}
