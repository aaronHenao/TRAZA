import 'package:flutter_riverpod/flutter_riverpod.dart';

/// De dónde sale la experiencia acumulada de la cuenta con la sesión abierta.
///
/// La progresión (SCRUM-178) solo la consulta: quién la suma y dónde se guarda
/// es del motor de experiencia, la historia que acredita XP al completar un
/// reto. Esta interfaz es la frontera entre las dos, para que esa historia
/// aterrice sin tocar nada de la progresión.
final experienciaRepositoryProvider = Provider<ExperienciaRepository>(
  (ref) => const ExperienciaSinMotor(),
);

/// Lectura de la experiencia acumulada.
abstract interface class ExperienciaRepository {
  /// La experiencia que el corredor tiene acreditada. Nunca negativa.
  Future<int> experienciaAcumulada();
}

/// La experiencia mientras el motor que la acredita no existe.
///
/// Devuelve cero, y cero es el dato correcto: hoy ninguna parte de la app
/// otorga XP ni la persiste —`retos_usuario` lo deja dicho en su migración—,
/// así que nadie tiene experiencia acreditada. No es un valor de relleno ni
/// una simulación de datos.
///
/// Cuando llegue esa historia, se cambia `experienciaRepositoryProvider` por
/// el repositorio que lea lo que decida persistir, y la progresión sigue igual.
class ExperienciaSinMotor implements ExperienciaRepository {
  const ExperienciaSinMotor();

  @override
  Future<int> experienciaAcumulada() async => 0;
}
