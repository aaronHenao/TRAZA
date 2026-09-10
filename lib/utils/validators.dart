final _regexCorreo = RegExp(r'^[\w.+-]+@([\w-]+\.)+[a-zA-Z]{2,}$');

String? validarCorreo(String? valor) {
  final correo = valor?.trim() ?? '';

  if (correo.isEmpty) {
    return 'Ingresa tu correo electrónico';
  }
    if (!_regexCorreo.hasMatch(correo)) {
    return 'Formato inválido. Ejemplo: tucorreo@ejemplo.com';
  }


  return null;
}
