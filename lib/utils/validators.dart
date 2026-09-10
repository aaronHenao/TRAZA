// Las regex se declaran fuera de las funciones para compilarse una sola vez,
// y no en cada pulsación del usuario.
final _regexCorreo = RegExp(r'^[\w.+-]+@([\w-]+\.)+[a-zA-Z]{2,}$');
final _regexMayuscula = RegExp(r'[A-Z]');
final _regexMinuscula = RegExp(r'[a-z]');
final _regexNumero = RegExp(r'[0-9]');

/// Cualquier carácter que no sea letra, número ni espacio.
final _regexEspecial = RegExp(r'[^A-Za-z0-9\s]');

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

/// A la contraseña no se le hace trim: los espacios pueden ser parte de ella.
String? validarPassword(String? valor) {
  final password = valor ?? '';

  if (password.isEmpty) {
    return 'Ingresa una contraseña';
  }
  if (password.length < 8) {
    return 'Debe tener al menos 8 caracteres';
  }
  if (!password.contains(_regexMayuscula)) {
    return 'Debe incluir al menos una letra mayúscula';
  }
  if (!password.contains(_regexMinuscula)) {
    return 'Debe incluir al menos una letra minúscula';
  }
  if (!password.contains(_regexNumero)) {
    return 'Debe incluir al menos un número';
  }
  if (!password.contains(_regexEspecial)) {
    return 'Debe incluir al menos un carácter especial';
  }

  return null;
}
