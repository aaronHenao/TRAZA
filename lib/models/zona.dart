/// Un lugar con nombre y la caja que lo contiene: un municipio, una comuna,
/// un barrio o un parque (SCRUM-255).
///
/// Buscar por zona devuelve las rutas que arrancan dentro de la caja, estén
/// lo lejos que estén del usuario (criterio 2 de HU-30).
class Zona {
  const Zona({
    required this.nombre,
    required this.sur,
    required this.oeste,
    required this.norte,
    required this.este,
    this.region,
  });

  final String nombre;

  /// El departamento, para distinguir lugares que se llaman igual: Belén es
  /// una comuna de Medellín y también un municipio de Boyacá. Null si no se
  /// sabe o si es el mismo nombre.
  final String? region;

  final double sur;
  final double oeste;
  final double norte;
  final double este;

  /// Como se le nombra al usuario: "Envigado, Antioquia".
  String get nombreCompleto => region == null ? nombre : '$nombre, $region';

  @override
  bool operator ==(Object other) =>
      other is Zona &&
      other.nombre == nombre &&
      other.region == region &&
      other.sur == sur &&
      other.oeste == oeste &&
      other.norte == norte &&
      other.este == este;

  @override
  int get hashCode => Object.hash(nombre, region, sur, oeste, norte, este);

  @override
  String toString() => 'Zona($nombreCompleto: $sur, $oeste, $norte, $este)';
}
