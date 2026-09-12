// Las regex se declaran fuera de las funciones para compilarse una sola vez,
// y no en cada pulsación del usuario.
final _regexCorreo = RegExp(r'^[\w.+-]+@([\w-]+\.)+[a-zA-Z]{2,}$');
final _regexMayuscula = RegExp(r'[A-Z]');
final _regexMinuscula = RegExp(r'[a-z]');
final _regexNumero = RegExp(r'[0-9]');

/// Cualquier carácter que no sea letra, número ni espacio.
final _regexEspecial = RegExp(r'[^A-Za-z0-9\s]');

String? validarNombre(String? valor) {
  final nombre = valor?.trim() ?? '';

  if (nombre.isEmpty) {
    return 'Ingresa tu nombre';
  }
  if (nombre.length < 2) {
    return 'Debe tener al menos 2 caracteres';
  }

  return null;
}

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

class ReglaPassword {
  const ReglaPassword({
    required this.descripcion,
    required this.mensajeError,
    required this.cumple,
  });

  /// Texto del checklist que se ve debajo del campo.
  final String descripcion;

  /// Texto en rojo que devuelve el validador cuando la regla falla.
  final String mensajeError;

  final bool Function(String password) cumple;
}

/// Única fuente de verdad de las reglas de contraseña. La usan el validador
/// y el checklist de la pantalla, así que nunca pueden quedar desalineados.
/// El orden importa: el validador reporta la primera regla que falle.
final reglasPassword = [
  ReglaPassword(
    descripcion: 'Mínimo 8 caracteres',
    mensajeError: 'Debe tener al menos 8 caracteres',
    cumple: (p) => p.length >= 8,
  ),
  ReglaPassword(
    descripcion: 'Una letra mayúscula',
    mensajeError: 'Debe incluir al menos una letra mayúscula',
    cumple: (p) => p.contains(_regexMayuscula),
  ),
  ReglaPassword(
    descripcion: 'Una letra minúscula',
    mensajeError: 'Debe incluir al menos una letra minúscula',
    cumple: (p) => p.contains(_regexMinuscula),
  ),
  ReglaPassword(
    descripcion: 'Un número',
    mensajeError: 'Debe incluir al menos un número',
    cumple: (p) => p.contains(_regexNumero),
  ),
  ReglaPassword(
    descripcion: 'Un carácter especial (no espacio)',
    mensajeError: 'Debe incluir al menos un carácter especial',
    cumple: (p) => p.contains(_regexEspecial),
  ),
];

/// A la contraseña no se le hace trim: los espacios pueden ser parte de ella.
String? validarPassword(String? valor) {
  final password = valor ?? '';

  if (password.isEmpty) {
    return 'Ingresa una contraseña';
  }
  for (final regla in reglasPassword) {
    if (!regla.cumple(password)) {
      return regla.mensajeError;
    }
  }

  return null;
}
