import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Lo mínimo que se queda un aviso, aunque diga dos palabras. En la feria se
/// vio que con 4 s el aviso se iba antes de que el usuario levantara la vista,
/// y quien lee despacio (o caminando) necesita un poco más.
const duracionMinimaToast = Duration(seconds: 6);

/// Lo máximo. Un texto que necesita más que esto no es un aviso: va en la
/// pantalla. Como el aviso se puede cerrar con su X, quedarse de más no
/// estorba.
const duracionMaximaToast = Duration(seconds: 10);

/// Lo que tarda alguien en notar que apareció el aviso y mirarlo.
const _tiempoParaNotarlo = Duration(seconds: 2);

/// Cuánto se lee cada carácter: unas 125 palabras por minuto, una lectura
/// sin apuro en el celular para quien todavía no conoce la app.
const _tiempoPorCaracter = Duration(milliseconds: 80);

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
/// en leerlo ([duracionDeToast]); un aviso nuevo reemplaza al anterior, y la
/// X lo cierra antes para quien ya lo leyó.
///
/// [mensaje] dice una sola cosa y cabe en dos renglones: unos 45 caracteres,
/// 60 como mucho si un criterio de la HU obliga a nombrar más. Lo que no cabe
/// ahí va en la pantalla.
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
        // La X no lo deja fijo: sin `action`, el aviso se sigue yendo solo.
        showCloseIcon: true,
        closeIconColor: Colors.white,
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
