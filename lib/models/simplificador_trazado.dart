import 'dart:math' as math;

import 'punto_gps.dart';
import 'tramos.dart';

/// Cuánto puede alejarse un punto de la línea que lo sustituye, en metros,
/// para que se pueda quitar sin cambiar la forma del recorrido (RNF-06).
///
/// 5 m es la misma separación con la que se graban los puntos
/// (`ConfiguracionRastreo.distanciaMinimaRegistroMetros`): por debajo de eso
/// un punto no aporta forma, solo el error del propio GPS. En una recta no
/// queda ninguno; en una curva quedan los que la dibujan.
const toleranciaSimplificacionMetros = 5.0;

/// Cuántos puntos conserva un trazado como máximo.
///
/// Vale para el que se guarda al publicar una ruta y para el que se dibuja
/// en el resumen: en los dos casos es el tope por encima del cual ni la
/// forma mejora ni la pantalla aguanta.
///
/// Con la tolerancia por defecto no suele hacer falta —una ruta de 10 km
/// cabe en bastante menos—, así que esto es la red de seguridad.
const maxPuntosTrazado = 500;

/// Un recorrido con menos puntos y los cortes de sus pausas recolocados.
typedef RecorridoSimplificado = ({List<PuntoGps> puntos, List<int> cortes});

/// [puntos] con los que no hacen falta para dibujar la misma forma, por
/// Douglas-Peucker, y nunca más de [maximo] (RNF-06).
///
/// El recorrido se graba con un punto cada 5 m, así que una hora de carrera
/// deja miles. Repartirlos uniforme —uno de cada n, que es lo que se hacía
/// antes— adelgaza la lista pero deforma el camino: en una curva cerrada
/// quita los puntos que la describen y en una recta conserva muchos que no
/// aportan nada. Douglas-Peucker decide por geometría: se queda con los
/// puntos que se separan de la línea más de [toleranciaMetros] y tira el
/// resto.
///
/// [maximo] es la red de seguridad, no el mecanismo: con la tolerancia por
/// defecto una ruta real cabe de sobra, pero si un recorrido muy largo o
/// muy revirado aún pasara del tope, la tolerancia se va duplicando hasta
/// que entre. Nunca devuelve más de [maximo] puntos.
///
/// [cortes] son los índices donde empieza un tramo tras una pausa: cada
/// tramo se simplifica por separado, porque unirlos dejaría una línea recta
/// atravesando la pausa (BUG-005). Los cortes que devuelve apuntan ya a los
/// puntos que quedan.
///
/// Los extremos de cada tramo se conservan siempre. Eso importa para el
/// recorte de privacidad de RNF-04: **se recorta antes y se simplifica
/// después**, así que el primer y el último punto que entran aquí ya son los
/// recortados y salen intactos.
RecorridoSimplificado simplificarRecorrido(
  List<PuntoGps> puntos, {
  required int maximo,
  List<int> cortes = const [],
  double toleranciaMetros = toleranciaSimplificacionMetros,
}) {
  assert(maximo >= 2, 'un trazado necesita al menos dos puntos');

  if (puntos.length <= 2) {
    return (puntos: [...puntos], cortes: [...cortes]);
  }

  final tramos = dividirEnTramos(puntos, cortes);

  List<List<PuntoGps>> con(double tolerancia) => [
    for (final tramo in tramos) _douglasPeucker(tramo, tolerancia),
  ];
  int cuantos(List<List<PuntoGps>> tramos) =>
      tramos.fold<int>(0, (suma, tramo) => suma + tramo.length);

  var resultado = con(toleranciaMetros);
  if (cuantos(resultado) <= maximo) return _armar(resultado);

  // No cabe. Douglas-Peucker nunca devuelve más puntos al subir la
  // tolerancia, y con una suficientemente grande cada tramo se queda en sus
  // dos extremos, así que duplicando se llega siempre a algo que cabe.
  var sobra = toleranciaMetros;
  var justo = toleranciaMetros * 2;
  resultado = con(justo);
  while (cuantos(resultado) > maximo && justo < _toleranciaMaxima) {
    sobra = justo;
    justo *= 2;
    resultado = con(justo);
  }

  // Y ahora se afina entre las dos. Duplicar a ciegas puede pasarse de
  // largo: un recorrido en zigzag salta de conservarlo entero a quedarse en
  // dos puntos de una sola duplicación, y dos puntos no son su forma. La
  // bisección busca la tolerancia más pequeña que todavía cabe, que es el
  // trazo con más detalle de los que entran en el tope.
  for (var i = 0; i < 12; i++) {
    final media = (sobra + justo) / 2;
    final prueba = con(media);
    if (cuantos(prueba) <= maximo) {
      justo = media;
      resultado = prueba;
    } else {
      sobra = media;
    }
  }

  return _armar(resultado);
}

RecorridoSimplificado _armar(List<List<PuntoGps>> tramos) =>
    (puntos: [for (final tramo in tramos) ...tramo], cortes: _cortesDe(tramos));

/// Más allá de esto no se sigue subiendo la tolerancia: con un recorrido
/// terrestre cualquiera, cada tramo ya está en sus dos extremos.
const _toleranciaMaxima = 40e6;

/// Índices de [puntos] que conserva Douglas-Peucker con [toleranciaMetros].
///
/// Expuesto aparte porque es la pieza que se prueba sola: dice *qué* se
/// conserva, sin construir nada.
List<int> indicesQueConserva(
  List<PuntoGps> puntos, {
  double toleranciaMetros = toleranciaSimplificacionMetros,
}) {
  if (puntos.length <= 2) {
    return [for (var i = 0; i < puntos.length; i++) i];
  }

  final conservar = List<bool>.filled(puntos.length, false);
  conservar[0] = true;
  conservar[puntos.length - 1] = true;

  // Pila propia en vez de recursión: un recorrido de miles de puntos puede
  // anidar tanto como puntos tenga (la partición de Douglas-Peucker no está
  // equilibrada), y eso desborda la pila de llamadas.
  final pendientes = <List<int>>[
    [0, puntos.length - 1],
  ];

  while (pendientes.isNotEmpty) {
    final [desde, hasta] = pendientes.removeLast();
    if (hasta - desde < 2) continue;

    var masLejano = -1;
    var mayorDistancia = 0.0;
    for (var i = desde + 1; i < hasta; i++) {
      final distancia = _distanciaAlSegmentoMetros(
        puntos[i],
        puntos[desde],
        puntos[hasta],
      );
      if (distancia > mayorDistancia) {
        mayorDistancia = distancia;
        masLejano = i;
      }
    }

    if (masLejano < 0 || mayorDistancia <= toleranciaMetros) continue;

    conservar[masLejano] = true;
    pendientes.add([desde, masLejano]);
    pendientes.add([masLejano, hasta]);
  }

  return [
    for (var i = 0; i < puntos.length; i++)
      if (conservar[i]) i,
  ];
}

List<PuntoGps> _douglasPeucker(List<PuntoGps> puntos, double tolerancia) => [
  for (final i in indicesQueConserva(puntos, toleranciaMetros: tolerancia))
    puntos[i],
];

List<int> _cortesDe(List<List<PuntoGps>> tramos) {
  final cortes = <int>[];
  var acumulado = 0;
  for (final tramo in tramos) {
    if (acumulado > 0) cortes.add(acumulado);
    acumulado += tramo.length;
  }
  return cortes;
}

/// Distancia de [punto] al segmento [a]–[b], en metros.
///
/// A la escala de un entrenamiento la Tierra se puede tratar como un plano:
/// un grado de latitud mide siempre lo mismo y uno de longitud mide
/// `cos(latitud)` veces eso. El error de esa aproximación en unos pocos km
/// es de centímetros, muy por debajo de la tolerancia y del error del GPS.
///
/// Se mide al **segmento**, no a la recta infinita que lo contiene: si el
/// punto más próximo cae fuera, vale la distancia al extremo. Eso resuelve
/// de paso el segmento de longitud cero —una ruta circular, donde el primer
/// y el último punto coinciden—, que se trata como la distancia a ese punto.
double _distanciaAlSegmentoMetros(PuntoGps punto, PuntoGps a, PuntoGps b) {
  const metrosPorGradoLatitud = 111320.0;
  final metrosPorGradoLongitud =
      metrosPorGradoLatitud * math.cos(a.latitud * math.pi / 180);

  final px = (punto.longitud - a.longitud) * metrosPorGradoLongitud;
  final py = (punto.latitud - a.latitud) * metrosPorGradoLatitud;
  final bx = (b.longitud - a.longitud) * metrosPorGradoLongitud;
  final by = (b.latitud - a.latitud) * metrosPorGradoLatitud;

  final largoCuadrado = bx * bx + by * by;
  // Segmento de longitud cero: no hay dirección sobre la que proyectar, así
  // que la distancia es al punto.
  if (largoCuadrado == 0) return math.sqrt(px * px + py * py);

  final avance = ((px * bx + py * by) / largoCuadrado).clamp(0.0, 1.0);
  final dx = px - avance * bx;
  final dy = py - avance * by;
  return math.sqrt(dx * dx + dy * dy);
}
