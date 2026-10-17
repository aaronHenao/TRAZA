import 'package:flutter/foundation.dart';

/// Los roles que se desbloquean corriendo (SCRUM-225).
///
/// No están aquí 'usuario' ni 'admin': esos son el tipo de cuenta y viven en
/// `perfiles.rol`, se asignan a mano y no se ganan. Un rol de estos se suma al
/// que la cuenta ya tenga.
enum RolGanable {
  /// Da acceso a las funcionalidades exclusivas de SCRUM-224.
  experto(valorDb: 'experto', nombre: 'Runner Experto');

  const RolGanable({required this.valorDb, required this.nombre});

  /// Como se guarda en la columna `rol` de `roles_usuario`.
  final String valorDb;

  /// Como se le nombra al usuario.
  final String nombre;

  /// El rol que corresponde a [valor], o null si la base trae uno que esta
  /// versión de la app no conoce.
  ///
  /// Devolver null y no lanzar es a propósito: los roles los añade una
  /// migración, así que una app vieja puede encontrarse con uno nuevo. Ignorar
  /// el que no entiende es preferible a no poder leer ninguno.
  static RolGanable? desdeValorDb(String valor) {
    for (final rol in RolGanable.values) {
      if (rol.valorDb == valor) return rol;
    }
    return null;
  }
}

/// Un rol que el corredor ya desbloqueó, tal como vive en `roles_usuario`.
@immutable
class RolGanado {
  const RolGanado({
    required this.rol,
    required this.otorgadoEn,
    this.anunciadoEn,
  });

  final RolGanable rol;

  /// Cuándo lo desbloqueó. No cambia aunque vuelva a cumplir la condición
  /// (criterio 5 de SCRUM-224).
  final DateTime otorgadoEn;

  /// Cuándo se le avisó, o null si todavía no se le ha anunciado.
  final DateTime? anunciadoEn;

  /// Si ya se le contó que lo tiene. Mientras sea false, la app debe
  /// anunciarlo (criterio 2).
  bool get anunciado => anunciadoEn != null;

  /// Lee una fila de `roles_usuario`.
  ///
  /// Lanza [FormatException] si la fila no encaja con el esquema, igual que
  /// `Nivel.desdeSupabase`: eso se arregla, no se disimula. La excepción es el
  /// rol desconocido, que devuelve null —ver [RolGanable.desdeValorDb]—.
  static RolGanado? desdeSupabase(Map<String, dynamic> fila) {
    final valorRol = fila['rol'];
    final otorgado = fila['otorgado_en'];
    final anunciado = fila['anunciado_en'];

    if (valorRol is! String ||
        otorgado is! String ||
        (anunciado != null && anunciado is! String)) {
      throw FormatException('Fila de roles_usuario inesperada', fila);
    }

    final rol = RolGanable.desdeValorDb(valorRol);
    if (rol == null) return null;

    return RolGanado(
      rol: rol,
      otorgadoEn: DateTime.parse(otorgado).toLocal(),
      anunciadoEn: anunciado == null
          ? null
          : DateTime.parse(anunciado as String).toLocal(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RolGanado &&
      other.rol == rol &&
      other.otorgadoEn == otorgadoEn &&
      other.anunciadoEn == anunciadoEn;

  @override
  int get hashCode => Object.hash(rol, otorgadoEn, anunciadoEn);

  @override
  String toString() =>
      'RolGanado(${rol.valorDb}, otorgado: $otorgadoEn, '
      'anunciado: ${anunciadoEn ?? 'todavía no'})';
}
