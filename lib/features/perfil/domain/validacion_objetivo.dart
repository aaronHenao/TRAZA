import 'tipo_objetivo.dart';

/// Interpreta el texto de un campo de objetivo como número.
///
/// Acepta coma o punto como separador decimal, porque el teclado del usuario
/// puede ofrecer cualquiera de los dos. Devuelve null si el texto no representa
/// un número admisible para [tipo].
num? interpretarValorObjetivo(TipoObjetivo tipo, String texto) {
  final limpio = texto.trim().replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  return tipo.permiteDecimales ? double.tryParse(limpio) : int.tryParse(limpio);
}

/// Valida el texto que el usuario escribió como valor de un objetivo.
///
/// Devuelve el mensaje de error a mostrar, o null si el valor es aceptable.
/// El campo de la interfaz ya filtra lo que se puede teclear, pero la regla
/// vive aquí para tenerla en un solo sitio y poder probarla sin widgets.
String? validarValorObjetivo(TipoObjetivo tipo, String texto) {
  if (texto.trim().isEmpty) {
    return 'Ingresa ${tipo.nombreValor}';
  }

  final valor = interpretarValorObjetivo(tipo, texto);
  if (valor == null) {
    return tipo.permiteDecimales
        ? 'Ingresa un número válido'
        : 'Usa solo números enteros';
  }

  final maximo = tipo.maximo;
  if (maximo == null) {
    if (valor < tipo.minimo) {
      return 'El mínimo es '
          '${formatearValorObjetivo(tipo.minimo)} ${tipo.unidad}';
    }
  } else if (valor < tipo.minimo || valor > maximo) {
    return 'Debe estar entre ${formatearValorObjetivo(tipo.minimo)} y '
        '${formatearValorObjetivo(maximo)} ${tipo.unidad}';
  }

  return null;
}
