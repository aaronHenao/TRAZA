import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/nuevo_reto.dart';
import '../models/periodicidad_reto.dart';
import '../models/reto.dart';
import '../models/reto_del_usuario.dart';
import 'reloj_provider.dart';
import 'retos_service.dart';

/// Cómo terminó un intento de crear un reto.
///
/// Es un tipo cerrado para que la pantalla tenga que contemplar los tres
/// casos: se creó, los datos están mal, o no se pudo guardar. Cada uno se
/// muestra distinto — el primero navega, el segundo marca campos y el tercero
/// avisa sin perder lo escrito.
sealed class ResultadoCreacionReto {
  const ResultadoCreacionReto();
}

/// El reto quedó registrado. [reto] trae el id y el estado que puso la base.
class RetoCreado extends ResultadoCreacionReto {
  const RetoCreado(this.reto);

  final Reto reto;
}

/// El borrador no pasó las reglas: no se llegó a tocar la base.
///
/// [errores] viene por campo para poder señalar cuáles corregir (criterio 2
/// de SCRUM-132).
class RetoConErrores extends ResultadoCreacionReto {
  const RetoConErrores(this.errores);

  final Map<CampoReto, String> errores;
}

/// Los datos estaban bien pero el guardado falló. Lo escrito sigue intacto:
/// el administrador puede reintentar sin volver a llenar el formulario.
class RetoNoGuardado extends ResultadoCreacionReto {
  const RetoNoGuardado(this.mensaje);

  final String mensaje;
}

/// Qué conjunto de retos mira el administrador. Cambia la consulta.
final vistaGestionRetosProvider = StateProvider.autoDispose<VistaGestionRetos>(
  (ref) => VistaGestionRetos.vigentes,
);

/// Qué periodicidad muestra la gestión, o null para todas.
final filtroPeriodicidadRetosProvider =
    StateProvider.autoDispose<PeriodicidadReto?>((ref) => null);

/// Catálogo que ve el administrador, según la vista elegida.
///
/// Cada vista es una consulta distinta y no un filtro en memoria: separar lo
/// vigente de lo caducado depende de la fecha de hoy, que la base no conoce
/// —está en UTC— y que el cliente sí.
///
/// `autoDispose`: se vuelve a consultar cada vez que se entra, así el reto
/// recién creado aparece sin trucos (criterio 1 de SCRUM-132).
final catalogoRetosProvider = FutureProvider.autoDispose<List<Reto>>((
  ref,
) async {
  final repositorio = ref.watch(retosRepositoryProvider);
  final hoy = ref.read(relojProvider)();

  return switch (ref.watch(vistaGestionRetosProvider)) {
    VistaGestionRetos.vigentes => repositorio.vigentes(hoy: hoy),
    VistaGestionRetos.caducados => repositorio.caducados(hoy: hoy),
    VistaGestionRetos.retirados => repositorio.listar(
      estado: EstadoReto.retirado,
    ),
  };
});

/// El catálogo ya filtrado por periodicidad.
///
/// La periodicidad se filtra aquí y no en la consulta: el catálogo de un
/// administrador cabe de sobra en memoria, y así cambiar de pestaña responde
/// al instante en vez de ir a la red.
final retosFiltradosProvider = Provider.autoDispose<AsyncValue<List<Reto>>>((
  ref,
) {
  final periodicidad = ref.watch(filtroPeriodicidadRetosProvider);
  return ref
      .watch(catalogoRetosProvider)
      .whenData(
        (retos) => periodicidad == null
            ? retos
            : retos.where((reto) => reto.periodicidad == periodicidad).toList(),
      );
});

/// Los retos que el corredor puede intentar hoy (SCRUM-163).
///
/// `autoDispose`: se consulta al entrar a la sección, así un reto que acaba
/// de vencer deja de aparecer sin tener que reiniciar la app.
final retosVigentesProvider = FutureProvider.autoDispose<List<Reto>>(
  (ref) => ref
      .watch(retosRepositoryProvider)
      .vigentes(hoy: ref.read(relojProvider)()),
);

/// Separa el catálogo en lo que el corredor ya lleva y lo que puede tomar,
/// y marca de esto último lo que su regla de un reto por hueco no le deja.
VistaRetosCorredor _repartir(
  List<Reto> catalogo,
  List<RetoDelUsuario> activados,
  DateTime ahora,
) {
  final enCurso = activados.where((mio) => mio.enCursoEn(ahora)).toList();
  final disponibles = catalogo
      .where((reto) => !activados.any((mio) => mio.reto.id == reto.id))
      .toList();

  return (
    enCurso: enCurso,
    disponibles: disponibles,
    bloqueados: {
      // La entrada desaparece sola cuando no hay motivo.
      for (final reto in disponibles) reto.id: ?motivoDeBloqueo(reto, enCurso),
    },
  );
}

/// Qué periodicidad está mirando el corredor, o null para todas.
///
/// Se filtra en memoria y no en la consulta: los retos vigentes de un día son
/// pocos, y así cambiar de pestaña responde al instante.
final filtroRetosCorredorProvider =
    StateProvider.autoDispose<PeriodicidadReto?>((ref) => null);

/// Qué pestaña del historial está abierta. Arranca en lo que el corredor
/// todavía puede cumplir.
final seccionHistorialRetosProvider =
    StateProvider.autoDispose<SeccionHistorialRetos>(
      (ref) => SeccionHistorialRetos.enCurso,
    );

/// Los retos que el corredor ha activado (SCRUM-173 y SCRUM-174).
final misRetosProvider = FutureProvider.autoDispose<List<RetoDelUsuario>>(
  (ref) => ref.watch(retosRepositoryProvider).misRetos(),
);

/// Lo que el corredor ve en Retos: lo que tiene en juego y lo que puede
/// activar (SCRUM-170).
typedef VistaRetosCorredor = ({
  List<RetoDelUsuario> enCurso,
  List<Reto> disponibles,

  /// Los de [disponibles] que hoy no se pueden activar, con el motivo listo
  /// para mostrar. Se marcan en vez de esconderse: un reto que desaparece sin
  /// explicación se lee como un fallo.
  Map<String, String> bloqueados,
});

/// Por qué no se puede activar [reto] teniendo [enCurso] entre manos, o null
/// si sí se puede.
///
/// Es la misma regla del trigger `retos_usuario_un_reto_por_hueco`: un reto
/// por pareja de periodicidad y tipo de actividad, comparando vigencias. Aquí
/// está para poder decirlo antes, no para sustituirla.
String? motivoDeBloqueo(Reto reto, List<RetoDelUsuario> enCurso) {
  final choca = enCurso.any(
    (mio) =>
        mio.reto.periodicidad == reto.periodicidad &&
        mio.reto.tipoActividad == reto.tipoActividad &&
        mio.reto.vigencia.solapaCon(reto.vigencia),
  );
  if (!choca) return null;

  return 'Ya tienes un reto ${reto.periodicidad.etiqueta.toLowerCase()} '
      'de ${reto.tipoActividad.nombre} en curso.';
}

/// Reparte los retos vigentes entre las dos secciones de la pantalla.
///
/// Un reto ya activado sale de "Disponibles": tenerlo en las dos listas haría
/// pensar que se puede activar otra vez, y la tabla no lo permitiría. También
/// salen los ya completados, porque un reto no se repite dentro de su
/// vigencia.
final retosCorredorProvider =
    Provider.autoDispose<AsyncValue<VistaRetosCorredor>>((ref) {
      final ahora = ref.read(relojProvider)();
      final vigentes = ref.watch(retosVigentesProvider);
      final mios = ref.watch(misRetosProvider);

      return switch ((vigentes, mios)) {
        (AsyncError(:final error, :final stackTrace), _) ||
        (
          _,
          AsyncError(:final error, :final stackTrace),
        ) => AsyncError(error, stackTrace),
        (AsyncData(value: final catalogo), AsyncData(value: final activados)) =>
          AsyncData(_repartir(catalogo, activados, ahora)),
        // Con una sola de las dos no se puede pintar nada: sin saber qué tiene
        // activado, el catálogo ofrecería retos que ya son suyos.
        _ => const AsyncLoading(),
      };
    });

/// Cómo terminó un intento de activar un reto.
///
/// Tipo cerrado para que la pantalla tenga que contemplar los dos casos: el
/// reto quedó activado, o no se pudo y hay algo que decirle al corredor.
sealed class ResultadoActivacion {
  const ResultadoActivacion();
}

/// El reto quedó registrado como en progreso.
class RetoActivado extends ResultadoActivacion {
  const RetoActivado(this.mio);

  final RetoDelUsuario mio;
}

/// No se pudo activar. Lo que el corredor estaba mirando sigue ahí.
class RetoNoActivado extends ResultadoActivacion {
  const RetoNoActivado(this.mensaje);

  final String mensaje;
}

/// Activación de un reto (SCRUM-168).
final activacionRetoProvider = Provider<ActivacionReto>(ActivacionReto.new);

/// Apunta al corredor a un reto del catálogo.
///
/// Al activarlo, el reto pasa a su lista de retos en curso con el progreso en
/// cero: activar es comprometerse, no haber avanzado.
class ActivacionReto {
  const ActivacionReto(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para activar retos.';
  static const yaActivado = 'Ya tienes este reto activo.';
  static const noSePudo = 'No pudimos activar el reto. Inténtalo de nuevo.';

  Future<ResultadoActivacion> activar(Reto reto) async {
    try {
      final mio = await _ref.read(retosRepositoryProvider).activar(reto);
      // El catálogo y el historial cambian con esto: el reto pasa a estar
      // activado y aparece en "En curso".
      _ref.invalidate(misRetosProvider);
      return RetoActivado(mio);
    } on RetoDelMismoHuecoException {
      // La pantalla ya lo marcaba: si se llegó hasta aquí, el reparto venía de
      // antes de activar el otro. Se refresca para que lo refleje.
      _ref.invalidate(misRetosProvider);
      return RetoNoActivado(
        'Ya tienes un reto ${reto.periodicidad.etiqueta.toLowerCase()} '
        'de ${reto.tipoActividad.nombre} en curso.',
      );
    } on RetoYaActivadoException {
      // No es un fallo que haya que reintentar: el reto ya está donde el
      // corredor quería. Se refresca el historial por si lo activó desde
      // otro dispositivo y esta pantalla aún no lo sabía.
      _ref.invalidate(misRetosProvider);
      return const RetoNoActivado(yaActivado);
    } on SesionRequeridaParaRetosException {
      return const RetoNoActivado(sinSesion);
    } catch (error) {
      debugPrint('No se pudo activar el reto: $error');
      return const RetoNoActivado(noSePudo);
    }
  }
}

/// Edición de retos ya publicados (SCRUM-147).
final edicionRetoProvider = Provider<EdicionReto>(EdicionReto.new);

/// Une la validación del borrador con el guardado de los cambios.
///
/// Reaprovecha [ResultadoCreacionReto]: los tres desenlaces son los mismos
/// —quedó guardado, hay campos que corregir, o no se pudo— y darles nombres
/// distintos obligaría a la pantalla a tratar dos veces lo mismo.
class EdicionReto {
  const EdicionReto(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para editar retos.';
  static const soloAdministrador = 'Solo el administrador puede editar retos.';
  static const noSePudo =
      'No se pudieron guardar los cambios. Inténtalo de '
      'nuevo.';
  static const datosRechazados =
      'Revisa los datos del reto: la base no los aceptó.';

  /// Lo que se le dice al administrador cuando la meta que escribió no queda
  /// por encima de lo que ya corrió alguien.
  ///
  /// [km] llega ya escrito: quien llama lo formatea con el mismo
  /// `TarjetaReto.textoKm` con el que se pintan los km en toda la app.
  static String metaPorDebajoDeLoCorrido(String km) =>
      'Un corredor ya lleva $km km. La meta tiene que quedar por encima: si '
      'no, lo dejaría sin poder completarlo.';

  /// Cómo van los corredores que están haciendo [reto] (SCRUM-151).
  ///
  /// Si la consulta falla se devuelve que no hay nadie: ni el aviso ni el
  /// bloqueo de la meta son la barrera de verdad —esa es el trigger
  /// `retos_cambios_permitidos`—, y no poder contarlos no es motivo para
  /// impedirle al administrador guardar.
  Future<ProgresoEnCurso> comoVanLosCorredores(Reto reto) async {
    try {
      return await _ref.read(retosRepositoryProvider).progresoEnCurso(reto);
    } catch (error) {
      debugPrint('No se pudo ver cómo van los corredores del reto: $error');
      return (corredores: 0, maximoKm: 0.0);
    }
  }

  Future<ResultadoCreacionReto> guardar(
    Reto original,
    BorradorReto borrador,
  ) async {
    final cambios = borrador.aCambios(original);
    if (cambios == null) return RetoConErrores(borrador.errores);

    try {
      final guardado = await _ref
          .read(retosRepositoryProvider)
          .editar(original, cambios);

      // El catálogo del administrador y el del corredor muestran lo editado
      // (SCRUM-152). También los retos del corredor, que llevan el reto
      // embebido y enseñarían la meta vieja.
      _ref.invalidate(catalogoRetosProvider);
      _ref.invalidate(retosVigentesProvider);
      _ref.invalidate(misRetosProvider);
      return RetoCreado(guardado);
    } on SesionRequeridaParaRetosException {
      return const RetoNoGuardado(sinSesion);
    } on SoloAdministradorException {
      return const RetoNoGuardado(soloAdministrador);
    } on DatosDeRetoInvalidosException catch (error) {
      // Aquí sí puede llegar sin que nada esté roto: el trigger
      // `retos_cambios_permitidos` rechaza mover de sitio un reto, y la
      // pantalla no ofrece esos cambios pero la API sí los acepta.
      debugPrint('La base rechazó los cambios del reto: $error');
      return const RetoNoGuardado(datosRechazados);
    } catch (error) {
      debugPrint('No se pudieron guardar los cambios: $error');
      return const RetoNoGuardado(noSePudo);
    }
  }
}

/// Creación de retos (SCRUM-143).
final creacionRetoProvider = Provider<CreacionReto>(CreacionReto.new);

/// Une la validación del borrador con el guardado en Supabase.
///
/// Es el único camino para registrar un reto: valida primero y solo entonces
/// escribe, así que un reto inválido no llega nunca a la base.
class CreacionReto {
  const CreacionReto(this._ref);

  final Ref _ref;

  static const sinSesion = 'Inicia sesión para crear retos.';
  static const soloAdministrador = 'Solo el administrador puede crear retos.';
  static const noSePudo = 'No se pudo crear el reto. Inténtalo de nuevo.';
  static const datosRechazados =
      'Revisa los datos del reto: la base no los aceptó.';

  Future<ResultadoCreacionReto> crear(BorradorReto borrador) async {
    // La vigencia depende de cuándo se crea el reto, así que el reloj se lee
    // en este momento y no antes (SCRUM-142).
    final reto = borrador.aNuevoReto(ahora: _ref.read(relojProvider)());
    if (reto == null) return RetoConErrores(borrador.errores);

    try {
      return RetoCreado(await _ref.read(retosRepositoryProvider).crear(reto));
    } on SesionRequeridaParaRetosException {
      return const RetoNoGuardado(sinSesion);
    } on SoloAdministradorException {
      return const RetoNoGuardado(soloAdministrador);
    } on DatosDeRetoInvalidosException catch (error) {
      // No debería pasar: el borrador valida las mismas reglas. Si ocurre, la
      // tabla y la validación de Dart se desalinearon.
      debugPrint('La base rechazó los datos del reto: $error');
      return const RetoNoGuardado(datosRechazados);
    } catch (error) {
      debugPrint('No se pudo crear el reto: $error');
      return const RetoNoGuardado(noSePudo);
    }
  }
}
