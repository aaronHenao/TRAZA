/// Lo que se le cuenta a quien todavía no conoce la app (SCRUM-278).
///
/// Vive en un modelo y no dentro de la pantalla porque el texto se revisa con
/// el equipo, que no tiene por qué leer código de interfaz para cambiar una
/// palabra.
///
/// El contenido sale del prototipo (identidad del splash y su lema) y de lo
/// que la app ya hace a día de hoy. No se promete nada que no exista: ver
/// [FuncionTraza].
abstract final class PresentacionTraza {
  /// El lema del prototipo.
  static const lema = 'Corre. Compite. Evoluciona.';

  /// Qué es TRAZA, en una frase. Responde al criterio 2 de SCRUM-277:
  /// registrar entrenamientos, competir en retos y avanzar de nivel.
  static const queEs =
      'TRAZA es una aplicación para correr: registra tus entrenamientos, te '
      'pone retos y te hace subir de nivel a medida que acumulas '
      'experiencia.';

  /// Lo que se le dice a quien la abre sin tener cuenta, para que sepa que
  /// mirar no lo obliga a registrarse.
  static const invitacion =
      'Mira lo que puedes hacer antes de crear tu cuenta.';

  /// Encabeza los pasos: de un vistazo, cómo se juega.
  static const comoFunciona = 'Cómo funciona';
}

/// El ciclo de la app en tres pasos (SCRUM-278).
///
/// Las funciones dicen *qué* se puede hacer; esto dice *cómo encajan*: correr
/// da experiencia, y la experiencia da niveles e insignias. Es lo que explica
/// la gamificación sin que nadie tenga que deducirla de una lista.
///
/// Son tres a propósito: con más deja de leerse de un vistazo.
enum PasoTraza {
  corres(numero: 1, texto: 'Sales a correr y TRAZA registra tu recorrido.'),
  ganas(numero: 2, texto: 'Cada actividad y cada reto te dan experiencia.'),
  avanzas(
    numero: 3,
    texto: 'La experiencia te sube de nivel y te da insignias.',
  );

  const PasoTraza({required this.numero, required this.texto});

  /// Qué puesto ocupa en el ciclo. Empieza en 1, como se le muestra.
  final int numero;

  /// El paso, en una frase.
  final String texto;
}

/// Las funciones principales que se le muestran al usuario (criterio 3 de
/// SCRUM-277).
///
/// Son las cinco que nombra el criterio, en el orden en que se viven: primero
/// se corre, eso da retos y experiencia, la experiencia da niveles e
/// insignias, y las rutas son a dónde ir después.
///
/// Cada una existe en la app, salvo [rutas], que es lo que el Sprint 3 está
/// construyendo (HU-29 y siguientes) y el prototipo ya muestra como sección
/// propia. Si al cerrar el sprint las rutas no entraran, hay que quitar esa
/// entrada antes de publicar: la presentación no puede prometer una pantalla
/// que no existe.
enum FuncionTraza {
  registrar(
    titulo: 'Registrar tus actividades',
    detalle:
        'Tu recorrido, tu tiempo y tu distancia, en vivo y guardados al '
        'terminar.',
  ),
  retos(
    titulo: 'Cumplir retos',
    detalle: 'Metas diarias, semanales y mensuales que te dan experiencia.',
  ),
  niveles(
    titulo: 'Subir de nivel',
    detalle: 'La experiencia que ganas te hace avanzar en la progresión.',
  ),
  insignias(
    titulo: 'Ganar insignias',
    detalle: 'Reconocimientos por lo que vas logrando, visibles en tu perfil.',
  ),
  rutas(
    titulo: 'Explorar rutas',
    detalle: 'Recorridos publicados por la comunidad, cerca de donde estás.',
  );

  const FuncionTraza({required this.titulo, required this.detalle});

  /// Cómo se nombra la función. Cabe en una línea de la tarjeta.
  final String titulo;

  /// Qué significa, en una frase. Dos líneas como mucho.
  final String detalle;
}
