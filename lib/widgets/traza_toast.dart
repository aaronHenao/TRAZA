import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Lo mínimo que se queda un aviso, aunque diga dos palabras: es lo que pide
/// Material para un aviso que se va solo.
const duracionMinimaToast = Duration(seconds: 4);

/// Lo máximo. Un texto que necesita más que esto no es un aviso: va en la
/// pantalla.
const duracionMaximaToast = Duration(seconds: 8);

/// Lo que tarda alguien en notar que apareció el aviso y mirarlo.
const _tiempoParaNotarlo = Duration(milliseconds: 1500);

/// Cuánto se lee cada carácter: unas 180 palabras por minuto, una lectura
/// cómoda en el celular para quien todavía no conoce la app.
const _tiempoPorCaracter = Duration(milliseconds: 60);

/// Cuánto se queda [mensaje] en pantalla: lo que se tarda en notarlo y en
/// leerlo, entre [duracionMinimaToast] y [duracionMaximaToast].
///
/// Con un tiempo fijo, los avisos largos se iban antes de terminar de
/// leerlos y un usuario nuevo no alcanzaba a enterarse de qué pasó.
Duration duracionDeToast(String mensaje) {
  final lectura = _tiempoParaNotarlo + _tiempoPorCaracter * mensaje.length;
  if (lectura < duracionMinimaToast) return duracionMinimaToast;
  if (lectura > duracionMaximaToast) return duracionMaximaToast;
  return lectura;
}

/// Aviso breve al pie de la pantalla (`.toast` del prototipo).
///
/// Se apoya en el [ScaffoldMessenger] raíz de la app, así que el mensaje sigue
/// visible aunque justo después se cambie de pantalla. Dura lo que se tarda
/// en leerlo ([duracionDeToast]); un aviso nuevo reemplaza al anterior.
///
/// [separacionInferior] sube el aviso cuando al pie hay botones que no debe
/// tapar.
void mostrarToast(
  BuildContext context,
  String mensaje, {
  double separacionInferior = 24,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        margin: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          separacionInferior,
        ),
        duration: duracionDeToast(mensaje),
      ),
    );
}
