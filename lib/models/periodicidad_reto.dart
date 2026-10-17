import 'vigencia_reto.dart';

/// Cada cuánto se renueva un reto.
///
/// Los nombres del enum coinciden con los valores que acepta la restricción
/// `periodicidad in ('diaria', 'semanal', 'mensual')` de la tabla `retos`
/// (`supabase/migrations/0006_retos.sql`), así que [valorDb] no traduce nada.
enum PeriodicidadReto {
  diaria(etiqueta: 'Diario'),
  semanal(etiqueta: 'Semanal'),
  mensual(etiqueta: 'Mensual');

  const PeriodicidadReto({required this.etiqueta});

  /// Cómo se nombra en la interfaz: el reto es diario, no "de periodicidad
  /// diaria".
  final String etiqueta;

  String get valorDb => name;

  /// La periodicidad que Supabase devolvió, o null si el valor no es ninguna
  /// de las conocidas.
  static PeriodicidadReto? desdeDb(String? valor) {
    for (final periodicidad in values) {
      if (periodicidad.valorDb == valor) return periodicidad;
    }
    return null;
  }

  /// La vigencia que le toca a un reto de esta periodicidad creado en [ahora]
  /// (SCRUM-142).
  ///
  /// Es el período **en curso**, no uno que empiece mañana: el administrador
  /// crea el reto para que los corredores lo vean ya. De ahí que un reto
  /// semanal creado un jueves empiece el lunes de esa misma semana.
  ///
  /// El administrador no escribe estas fechas: las ve calculadas y no puede
  /// cambiarlas, porque son lo que define la periodicidad.
  VigenciaReto vigenciaDesde(DateTime ahora) {
    final hoy = VigenciaReto.soloFecha(ahora);

    return switch (this) {
      // Empieza y termina hoy.
      PeriodicidadReto.diaria => VigenciaReto(inicio: hoy, fin: hoy),

      // De lunes a domingo, como el calendario local.
      PeriodicidadReto.semanal => _semanaDe(hoy),

      // Del día 1 al último del mes, sea de 28, 29, 30 o 31 días.
      PeriodicidadReto.mensual => VigenciaReto(
        inicio: DateTime(hoy.year, hoy.month, 1),
        // Día 0 del mes siguiente es el último de este; en diciembre, el mes
        // 13 rueda a enero del año siguiente sin ayuda.
        fin: DateTime(hoy.year, hoy.month + 1, 0),
      ),
    };
  }

  static VigenciaReto _semanaDe(DateTime hoy) {
    // `weekday` va de 1 (lunes) a 7 (domingo).
    //
    // Se suman y restan días del calendario, no duraciones: en una zona con
    // cambio de hora un día no siempre dura 24 h, y restar 72 h exactas
    // podría caer en el día anterior a las 23:00.
    final lunes = DateTime(
      hoy.year,
      hoy.month,
      hoy.day - (hoy.weekday - DateTime.monday),
    );
    return VigenciaReto(
      inicio: lunes,
      fin: DateTime(lunes.year, lunes.month, lunes.day + 6),
    );
  }
}
