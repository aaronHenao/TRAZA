import 'package:traza/models/nuevo_reto.dart';
import 'package:traza/models/reto.dart';
import 'package:traza/models/reto_del_usuario.dart';
import 'package:traza/services/retos_service.dart';

/// Base para los dobles de `RetosRepository`.
///
/// Cada prueba sobrescribe solo lo que use. Existe para que añadir un método
/// al repositorio no obligue a tocar todos los archivos de prueba que ya
/// tenían un doble.
abstract class RetosRepositorioFalso implements RetosRepository {
  @override
  Future<Reto> crear(NuevoReto reto) => throw UnimplementedError();

  @override
  Future<Reto> editar(Reto original, CambiosReto cambios) =>
      throw UnimplementedError();

  @override
  Future<Reto> retirar(Reto reto) => throw UnimplementedError();

  @override
  Future<CorredoresDelReto> corredoresDe(Reto reto) async =>
      (enProgreso: 0, completados: 0, maximoKm: 0.0);

  @override
  Future<List<Reto>> listar({EstadoReto estado = EstadoReto.activo}) async =>
      const [];

  @override
  Future<List<Reto>> vigentes({required DateTime hoy}) async => const [];

  @override
  Future<List<Reto>> caducados({required DateTime hoy}) async => const [];

  @override
  Future<RetoDelUsuario> activar(Reto reto) => throw UnimplementedError();

  @override
  Future<List<RetoDelUsuario>> misRetos() async => const [];
}
