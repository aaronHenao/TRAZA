const _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// `Hoy`, `Ayer`, `14 sep` o `14 sep 2025`: cuándo pasó [fecha] visto desde
/// [ahora], con el mismo criterio que el historial de entrenamientos.
String fechaRelativa(DateTime fecha, DateTime ahora) {
  final dia = fecha.toLocal();
  final hoy = ahora.toLocal();
  // Días de calendario, en UTC para que un cambio de horario no convierta un
  // día en 23 horas.
  final dias = DateTime.utc(
    hoy.year,
    hoy.month,
    hoy.day,
  ).difference(DateTime.utc(dia.year, dia.month, dia.day)).inDays;

  if (dias == 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  final texto = '${dia.day} ${_meses[dia.month - 1]}';
  return dia.year == hoy.year ? texto : '$texto ${dia.year}';
}

/// Como [fechaRelativa] pero con la hora: `Hoy, 3:05 p. m.`. Sirve donde dos
/// cosas del mismo día se tienen que distinguir, como las versiones de una
/// publicación editada.
String fechaYHoraRelativa(DateTime fecha, DateTime ahora) {
  final local = fecha.toLocal();
  final hora12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minutos = local.minute.toString().padLeft(2, '0');
  final sufijo = local.hour < 12 ? 'a. m.' : 'p. m.';
  return '${fechaRelativa(fecha, ahora)}, $hora12:$minutos $sufijo';
}
