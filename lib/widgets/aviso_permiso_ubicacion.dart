import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/estado_permisos.dart';
import '../services/permisos_provider.dart';
import 'tarjeta_aviso.dart';
import 'traza_toast.dart';

/// Explica para qué hace falta la ubicación y ofrece concederla.
///
/// Es el mismo aviso en el carrusel de la portada (SCRUM-290) y en Explorar
/// rutas (SCRUM-248, criterio 3 de HU-29), para que el usuario lea lo mismo
/// en los dos sitios. No bloquea nada: va en el lugar de lo que se mostraría
/// con la ubicación, y el resto de la pantalla sigue en pie.
///
/// Si el usuario lo negó para siempre, el sistema ya no muestra su ventana y
/// lo único que queda es ir a los ajustes del teléfono. Al volver de ahí el
/// permiso se consulta otra vez solo: si lo concedió, el aviso desaparece y
/// la pantalla se pone al día sin que tenga que hacer nada.
class AvisoPermisoUbicacion extends ConsumerStatefulWidget {
  const AvisoPermisoUbicacion({this.enNavegador = kIsWeb, super.key});

  /// Si la app corre en un navegador.
  ///
  /// Ahí el permiso es de la página, no de una app instalada, y no hay
  /// ajustes que abrir desde aquí: en la web `openAppSettings` no existe y
  /// lanza un error. Bloqueado —por ejemplo, tras "No permitir nunca"—, el
  /// navegador ya no deja preguntar: se explica cómo activarlo junto a la
  /// dirección y el botón vuelve a revisar. Por defecto, lo que diga la
  /// plataforma.
  final bool enNavegador;

  static const clave = Key('aviso-permiso-ubicacion');
  static const claveBoton = Key('aviso-permiso-ubicacion-boton');

  static const titulo = 'Ve las rutas que tienes cerca';

  /// Por qué se pide (criterio 3 de HU-29).
  static const porQue =
      'TRAZA usa tu ubicación para ordenarlas de la más cercana a la más '
      'lejana.';

  /// Lo que se dice cuando el sistema ya no deja pedirlo.
  static const comoActivarlo =
      'El permiso de ubicación está desactivado para TRAZA. Actívalo en los '
      'ajustes del teléfono.';

  /// Lo mismo en un navegador, donde se activa junto a la dirección.
  static const comoActivarloEnNavegador =
      'El navegador tiene bloqueada la ubicación para TRAZA. Actívala desde '
      'el icono junto a la dirección de la página y toca «Revisar de nuevo».';

  /// Lo que se dice si al revisar sigue bloqueada. Sin esto, el botón
  /// parecería no hacer nada.
  static const sigueBloqueadaEnNavegador =
      'La ubicación sigue bloqueada en el navegador.';

  @override
  ConsumerState<AvisoPermisoUbicacion> createState() =>
      _AvisoPermisoUbicacionState();
}

class _AvisoPermisoUbicacionState extends ConsumerState<AvisoPermisoUbicacion> {
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    // Si fue a los ajustes del teléfono y lo concedió allá, al volver a la
    // app se nota solo. Solo escucha mientras el aviso está a la vista, que
    // es justo cuando falta el permiso.
    _ciclo = AppLifecycleListener(
      onResume: () => ref.read(permisosProvider.notifier).actualizar(),
    );
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  /// En el navegador: vuelve a consultar el permiso después de que el
  /// usuario lo activó junto a la dirección. Si ya está, quien muestra el
  /// aviso deja de mostrarlo; si no, se dice, para que el toque no se
  /// pierda sin respuesta.
  Future<void> _revisarDeNuevo() async {
    await ref.read(permisosProvider.notifier).actualizar();
    if (!mounted) return;
    if (ref.read(permisosProvider).ubicacion == EstadoPermiso.bloqueado) {
      mostrarToast(context, AvisoPermisoUbicacion.sigueBloqueadaEnNavegador);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permisos = ref.watch(permisosProvider);
    final bloqueado = permisos.ubicacion == EstadoPermiso.bloqueado;
    final notificador = ref.read(permisosProvider.notifier);

    // El botón dice lo que va a pasar: pedirlo aquí mismo, ir a los ajustes
    // del teléfono —que es salir de la app— o, en el navegador, revisar otra
    // vez después de activarlo junto a la dirección.
    final String explicacion;
    final String etiqueta;
    final VoidCallback accion;
    if (!bloqueado) {
      explicacion = AvisoPermisoUbicacion.porQue;
      etiqueta = 'Aceptar';
      accion = notificador.solicitarUbicacion;
    } else if (widget.enNavegador) {
      explicacion = AvisoPermisoUbicacion.comoActivarloEnNavegador;
      etiqueta = 'Revisar de nuevo';
      accion = _revisarDeNuevo;
    } else {
      explicacion = AvisoPermisoUbicacion.comoActivarlo;
      etiqueta = 'Abrir ajustes';
      accion = notificador.abrirAjustes;
    }

    return TarjetaAviso(
      key: AvisoPermisoUbicacion.clave,
      icono: Icons.location_off_outlined,
      titulo: AvisoPermisoUbicacion.titulo,
      texto: explicacion,
      etiquetaBoton: etiqueta,
      claveBoton: AvisoPermisoUbicacion.claveBoton,
      // Mientras la ventana del sistema está abierta no se puede pedir otra
      // vez: el segundo toque no haría nada útil.
      onBoton: permisos.solicitandoUbicacion ? null : accion,
    );
  }
}
