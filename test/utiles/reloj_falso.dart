/// Reloj falso compartido por las pruebas: el tiempo solo avanza
/// cuando la prueba lo dice.
class RelojFalso {
  RelojFalso([DateTime? inicio]) : _ahora = inicio ?? DateTime(2026, 1, 1, 8);

  DateTime _ahora;

  DateTime call() => _ahora;

  void avanzar(Duration cuanto) => _ahora = _ahora.add(cuanto);
}
