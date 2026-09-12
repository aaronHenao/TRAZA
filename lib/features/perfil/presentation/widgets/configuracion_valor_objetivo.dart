import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../domain/tipo_objetivo.dart';
import '../perfil_notifier.dart';

/// Fila para escribir el valor de un objetivo (`.goal-input-row` del
/// prototipo): campo numérico, unidad y mensaje de validación.
///
/// Se dibuja dentro de [ObjetivoCard] solo cuando el objetivo está marcado.
/// Es un [ConsumerStatefulWidget] únicamente por el [TextEditingController]:
/// el valor en sí vive en el estado del perfil, no aquí.
class ConfiguracionValorObjetivo extends ConsumerStatefulWidget {
  const ConfiguracionValorObjetivo({required this.tipo, super.key});

  final TipoObjetivo tipo;

  @override
  ConsumerState<ConfiguracionValorObjetivo> createState() =>
      _ConfiguracionValorObjetivoState();
}

class _ConfiguracionValorObjetivoState
    extends ConsumerState<ConfiguracionValorObjetivo> {
  late final TextEditingController _texto;

  @override
  void initState() {
    super.initState();
    // El texto vive en el estado del perfil, así que al volver a marcar el
    // objetivo reaparece lo último que escribió el usuario.
    _texto = TextEditingController(
      text: ref.read(perfilProvider).textoDe(widget.tipo),
    );
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(
      perfilProvider.select((estado) => estado.errorDe(widget.tipo)),
    );
    final invalido = error != null;

    return GestureDetector(
      // Equivale al event.stopPropagation() del prototipo: tocar el campo o la
      // unidad no debe desmarcar la tarjeta.
      onTap: () {},
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: widget.tipo.permiteDecimales ? 96 : 72,
                child: TextField(
                  controller: _texto,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: widget.tipo.permiteDecimales,
                  ),
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    _FormatoNumerico(
                      decimales: widget.tipo.maxDecimales,
                      maxCaracteres: widget.tipo.maxCaracteres,
                    ),
                  ],
                  onChanged: (valor) => ref
                      .read(perfilProvider.notifier)
                      .actualizarValor(widget.tipo, valor),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: invalido ? AppColors.dangerTint : AppColors.bg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 9,
                    ),
                    enabledBorder: _borde(
                      invalido ? AppColors.danger : AppColors.line,
                    ),
                    focusedBorder: _borde(
                      invalido ? AppColors.danger : AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.tipo.unidad,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink2,
                ),
              ),
            ],
          ),
          if (invalido) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static OutlineInputBorder _borde(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: BorderSide(color: color, width: 1.5),
  );
}

/// Deja teclear un número con hasta [decimales] cifras decimales, aceptando
/// coma o punto como separador. [maxCaracteres] solo evita que el número
/// desborde la caja; no es una regla de negocio.
class _FormatoNumerico extends TextInputFormatter {
  _FormatoNumerico({required this.decimales, required this.maxCaracteres});

  final int decimales;
  final int maxCaracteres;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    if (nuevo.text.isEmpty) return nuevo;
    if (nuevo.text.length > maxCaracteres) return anterior;

    final patron = decimales == 0
        ? RegExp(r'^\d+$')
        : RegExp('^\\d*([.,]\\d{0,$decimales})?\$');

    return patron.hasMatch(nuevo.text) ? nuevo : anterior;
  }
}
