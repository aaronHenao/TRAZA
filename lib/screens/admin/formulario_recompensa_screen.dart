import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/recompensa.dart';
import '../../services/recompensas_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Formulario con el que el administrador crea una recompensa (SCRUM-374).
class FormularioRecompensaScreen extends ConsumerStatefulWidget {
  const FormularioRecompensaScreen({super.key});

  static const claveNombre = Key('recompensa-nombre');
  static const claveDescripcion = Key('recompensa-descripcion');
  static const clavePuntos = Key('recompensa-puntos');
  static const claveDisponible = Key('recompensa-disponible');
  static const claveGuardar = Key('recompensa-guardar');

  @override
  ConsumerState<FormularioRecompensaScreen> createState() =>
      _FormularioRecompensaScreenState();
}

class _FormularioRecompensaScreenState
    extends ConsumerState<FormularioRecompensaScreen> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _puntos = TextEditingController();
  bool _disponible = true;

  /// Los errores solo se pintan después del primer intento de guardar.
  /// Marcar en rojo lo que el administrador todavía no ha llegado a escribir
  /// sería regañarlo por adelantado.
  Map<CampoRecompensa, String> _errores = const {};

  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _puntos.dispose();
    super.dispose();
  }

  BorradorRecompensa get _borrador => BorradorRecompensa(
    nombre: _nombre.text,
    descripcion: _descripcion.text,
    puntos: _puntos.text,
    disponible: _disponible,
  );

  /// Quita el error de un campo en cuanto se toca, para que el rojo no se
  /// quede puesto mientras el administrador ya lo está corrigiendo.
  void _alEditar(CampoRecompensa campo) {
    if (!_errores.containsKey(campo)) return;
    setState(() => _errores = {..._errores}..remove(campo));
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final resultado = await ref
          .read(creacionRecompensaProvider)
          .crear(_borrador);
      if (!mounted) return;

      switch (resultado) {
        case RecompensaCreada():
          // `pop`: la gestión se refresca al recibir el control y la
          // recompensa aparece en la lista (criterio 1).
          context.pop();
          mostrarToast(context, 'Recompensa creada');
        case RecompensaConErrores(:final errores):
          // Criterio 2: no se crea y se señala cada campo.
          setState(() => _errores = errores);
          mostrarToast(context, 'Revisa los campos marcados');
        case RecompensaNoGuardada(:final mensaje):
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
              TrazaTopBar(titulo: 'Nueva recompensa', onAtras: context.pop),
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
                      clave: FormularioRecompensaScreen.claveNombre,
                      etiqueta: 'Nombre',
                      controlador: _nombre,
                      pista: 'Vale de hidratación',
                      error: _errores[CampoRecompensa.nombre],
                      maxCaracteres: maxCaracteresNombreRecompensa,
                      onCambio: () => _alEditar(CampoRecompensa.nombre),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Campo(
                      clave: FormularioRecompensaScreen.claveDescripcion,
                      etiqueta: 'Descripción',
                      controlador: _descripcion,
                      pista: 'Qué recibe el corredor y cómo lo reclama.',
                      error: _errores[CampoRecompensa.descripcion],
                      lineas: 3,
                      maxCaracteres: maxCaracteresDescripcionRecompensa,
                      onCambio: () => _alEditar(CampoRecompensa.descripcion),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Campo(
                      clave: FormularioRecompensaScreen.clavePuntos,
                      etiqueta: 'Puntos requeridos',
                      controlador: _puntos,
                      pista: '150',
                      sufijo: 'puntos',
                      error: _errores[CampoRecompensa.puntos],
                      // Sin filtrar a solo dígitos: si se cuela un signo o
                      // una coma, la validación lo explica en vez de
                      // borrarlo sin avisar.
                      teclado: TextInputType.number,
                      onCambio: () => _alEditar(CampoRecompensa.puntos),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      key: FormularioRecompensaScreen.claveDisponible,
                      value: _disponible,
                      onChanged: (valor) => setState(() => _disponible = valor),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Disponible',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      subtitle: const Text(
                        'Los corredores la ven en su catálogo.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.ink2),
                      ),
                    ),
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
/// debajo (criterio 2).
class _Campo extends StatelessWidget {
  const _Campo({
    required this.clave,
    required this.etiqueta,
    required this.controlador,
    required this.pista,
    required this.onCambio,
    this.error,
    this.sufijo,
    this.lineas = 1,
    this.maxCaracteres,
    this.teclado,
  });

  final Key clave;
  final String etiqueta;
  final TextEditingController controlador;
  final String pista;
  final VoidCallback onCambio;
  final String? error;
  final String? sufijo;
  final int lineas;
  final int? maxCaracteres;
  final TextInputType? teclado;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
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
          key: clave,
          controller: controlador,
          onChanged: (_) => onCambio(),
          maxLines: lineas,
          maxLength: maxCaracteres,
          keyboardType: teclado,
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
        ],
      ],
    );
  }

  static final _bordeError = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
  );
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
          key: FormularioRecompensaScreen.claveGuardar,
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
              : const Text('Crear recompensa'),
        ),
      ),
    );
  }
}
