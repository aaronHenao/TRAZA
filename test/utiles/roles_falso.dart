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

  @override
  Future<List<RolGanado>> misRoles() async {
    consultas++;
    final error = this.error;
    if (error != null) throw error;
    return roles;
  }
}
