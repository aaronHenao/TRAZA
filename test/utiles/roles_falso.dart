import 'package:traza/models/rol_ganado.dart';
import 'package:traza/services/roles_service.dart';

/// Roles ganados en memoria: responde lo que la prueba le indique y cuenta
/// cuántas veces se los pidieron.
class RolesFalso implements RolesRepository {
  RolesFalso({this.roles = const []});

  List<RolGanado> roles;

  /// Si no es null, la lectura lo lanza.
  Object? error;

  var consultas = 0;

  /// Atajo para la prueba que solo necesita una cuenta con el rol de experto.
  factory RolesFalso.experto({DateTime? otorgadoEn, DateTime? anunciadoEn}) =>
      RolesFalso(
        roles: [
          RolGanado(
            rol: RolGanable.experto,
            otorgadoEn: otorgadoEn ?? DateTime.utc(2026, 10, 2, 15),
            anunciadoEn: anunciadoEn,
          ),
        ],
      );

  /// Los roles que se marcaron como anunciados.
  final anunciados = <RolGanable>[];

  /// Cuántas veces se le pidió a la base revisar la cuenta.
  var evaluaciones = 0;

  @override
  Future<List<RolGanado>> misRoles() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return roles;
  }

  @override
  Future<void> evaluarMisRoles() async {
    evaluaciones++;
    final error = this.error;
    if (error != null) throw error;
  }

  @override
  Future<void> marcarAnunciado(RolGanable rol) async {
    anunciados.add(rol);
    // Como la base: la fecha se escribe una sola vez y la lectura siguiente ya
    // trae el rol anunciado.
    roles = [
      for (final ganado in roles)
        if (ganado.rol == rol && !ganado.anunciado)
          RolGanado(
            rol: ganado.rol,
            otorgadoEn: ganado.otorgadoEn,
            anunciadoEn: DateTime.utc(2026, 10, 4, 12),
          )
        else
          ganado,
    ];
  }
}
