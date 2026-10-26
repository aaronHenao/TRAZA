import 'package:flutter_test/flutter_test.dart';
import 'package:traza/models/recompensa.dart';

/// Reglas de una recompensa antes de registrarla (criterio 2 de SCRUM-374) y
/// lo que viaja hacia y desde la tabla `recompensas`.
void main() {
  const completo = BorradorRecompensa(
    nombre: 'Vale de hidratación',
    descripcion: 'Una bebida isotónica en la tienda aliada.',
    puntos: '150',
  );

  group('borrador completo', () {
    test('con nombre, descripción y puntos se puede registrar (criterio 1 de '
        'SCRUM-374)', () {
      expect(completo.errores, isEmpty);
      expect(completo.esValido, isTrue);
      expect(completo.puntosRequeridos, 150);
      expect(completo.aNuevaRecompensa(), isNotNull);
    });

    test('nace disponible si el administrador no dice lo contrario', () {
      expect(const BorradorRecompensa().disponible, isTrue);
      expect(completo.aNuevaRecompensa()!.disponible, isTrue);
    });

    test('marcada como no disponible se registra así (criterio 1 de '
        'SCRUM-374)', () {
      final oculta = completo.copyWith(disponible: false);

      expect(oculta.esValido, isTrue);
      expect(oculta.aNuevaRecompensa()!.disponible, isFalse);
      // copyWith no toca lo demás.
      expect(oculta.nombre, completo.nombre);
      expect(oculta.puntos, completo.puntos);
    });

    test('recorta los espacios sobrantes de nombre, descripción y puntos', () {
      final nueva = completo
          .copyWith(
            nombre: '  Vale de hidratación  ',
            descripcion: '\n Una bebida isotónica.  ',
            puntos: ' 150 ',
          )
          .aNuevaRecompensa()!;

      expect(nueva.nombre, 'Vale de hidratación');
      expect(nueva.descripcion, 'Una bebida isotónica.');
      expect(nueva.puntosRequeridos, 150);
    });
  });

  group('campos obligatorios (criterio 2 de SCRUM-374)', () {
    test('el borrador vacío señala los tres campos con su mensaje', () {
      const vacio = BorradorRecompensa();

      expect(vacio.errores, {
        CampoRecompensa.nombre: 'Ponle un nombre a la recompensa.',
        CampoRecompensa.descripcion: 'Describe en qué consiste.',
        CampoRecompensa.puntos: 'Indica cuántos puntos cuesta.',
      });
      expect(vacio.esValido, isFalse);
      expect(vacio.aNuevaRecompensa(), isNull);
    });

    test('sin nombre no se registra, y solo se marca el nombre', () {
      final sinNombre = completo.copyWith(nombre: '');

      expect(sinNombre.errores, {
        CampoRecompensa.nombre: 'Ponle un nombre a la recompensa.',
      });
      expect(sinNombre.aNuevaRecompensa(), isNull);
    });

    test('un nombre de solo espacios tampoco es un nombre', () {
      expect(
        completo.copyWith(nombre: '   ').errores[CampoRecompensa.nombre],
        'Ponle un nombre a la recompensa.',
      );
    });

    test('sin descripción no se registra, y solo se marca la descripción', () {
      final sinDescripcion = completo.copyWith(descripcion: ' \n ');

      expect(sinDescripcion.errores, {
        CampoRecompensa.descripcion: 'Describe en qué consiste.',
      });
      expect(sinDescripcion.aNuevaRecompensa(), isNull);
    });

    test('sin puntos no se registra', () {
      final sinPuntos = completo.copyWith(puntos: '');

      expect(sinPuntos.errores, {
        CampoRecompensa.puntos: 'Indica cuántos puntos cuesta.',
      });
      expect(sinPuntos.puntosRequeridos, isNull);
      expect(sinPuntos.aNuevaRecompensa(), isNull);
    });

    test('unos puntos de solo espacios cuentan como vacíos', () {
      expect(
        completo.copyWith(puntos: '   ').errores[CampoRecompensa.puntos],
        'Indica cuántos puntos cuesta.',
      );
    });
  });

  group('largo máximo', () {
    test('el nombre admite 60 caracteres y rechaza uno más', () {
      final enElLimite = completo.copyWith(
        nombre: 'a' * maxCaracteresNombreRecompensa,
      );
      final pasado = completo.copyWith(
        nombre: 'a' * (maxCaracteresNombreRecompensa + 1),
      );

      expect(maxCaracteresNombreRecompensa, 60);
      expect(enElLimite.errores, isEmpty);
      expect(pasado.errores, {CampoRecompensa.nombre: 'Máximo 60 caracteres.'});
      expect(pasado.aNuevaRecompensa(), isNull);
    });

    test('los espacios de los extremos no cuentan para el largo, como en el '
        'check de la tabla', () {
      final conEspacios = completo.copyWith(
        nombre: '  ${'a' * maxCaracteresNombreRecompensa}  ',
      );

      expect(conEspacios.errores, isEmpty);
    });

    test('la descripción admite 280 caracteres y rechaza uno más', () {
      final enElLimite = completo.copyWith(
        descripcion: 'a' * maxCaracteresDescripcionRecompensa,
      );
      final pasado = completo.copyWith(
        descripcion: 'a' * (maxCaracteresDescripcionRecompensa + 1),
      );

      expect(maxCaracteresDescripcionRecompensa, 280);
      expect(enElLimite.errores, isEmpty);
      expect(pasado.errores, {
        CampoRecompensa.descripcion: 'Máximo 280 caracteres.',
      });
    });
  });

  group('puntos mayores que cero (criterio 2 de SCRUM-374)', () {
    test('cero puntos no sirve', () {
      final cero = completo.copyWith(puntos: '0');

      expect(cero.errores, {
        CampoRecompensa.puntos: 'Los puntos deben ser mayores que cero.',
      });
      expect(cero.aNuevaRecompensa(), isNull);
    });

    test('unos puntos negativos tampoco', () {
      final negativo = completo.copyWith(puntos: '-5');

      expect(negativo.errores, {
        CampoRecompensa.puntos: 'Los puntos deben ser mayores que cero.',
      });
      expect(negativo.aNuevaRecompensa(), isNull);
    });

    test('un punto, el mínimo, sí sirve', () {
      final uno = completo.copyWith(puntos: '1');

      expect(uno.errores, isEmpty);
      expect(uno.aNuevaRecompensa()!.puntosRequeridos, 1);
    });

    test('admite hasta un millón de puntos y rechaza uno más, como el check '
        'de la tabla (criterio 2 de SCRUM-374)', () {
      expect(maxPuntosRecompensa, 1000000);
      expect(completo.copyWith(puntos: '1000000').errores, isEmpty);

      final pasado = completo.copyWith(puntos: '1000001');
      expect(pasado.errores, {
        CampoRecompensa.puntos: 'Máximo 1000000 puntos.',
      });
      expect(pasado.aNuevaRecompensa(), isNull);
    });

    test('un número que no cabe en la columna se señala en el campo en vez '
        'de fallar al guardar', () {
      expect(
        completo.copyWith(puntos: '2147483648').errores[CampoRecompensa.puntos],
        'Máximo 1000000 puntos.',
      );
    });

    test('lo que no es un número se distingue de lo que falta', () {
      final texto = completo.copyWith(puntos: 'abc');

      expect(texto.errores, {
        CampoRecompensa.puntos: 'Usa solo números enteros.',
      });
      expect(texto.puntosRequeridos, isNull);
      expect(texto.aNuevaRecompensa(), isNull);
    });

    test('los puntos no admiten decimales', () {
      final decimal = completo.copyWith(puntos: '2.5');

      expect(
        decimal.errores[CampoRecompensa.puntos],
        'Usa solo números enteros.',
      );
      expect(decimal.aNuevaRecompensa(), isNull);
    });
  });

  group('lo que se manda a Supabase', () {
    test('lleva exactamente las columnas que escribe el administrador', () {
      final fila = completo.aNuevaRecompensa()!.aSupabase();

      // Sin id ni fecha_creacion: los pone la base.
      expect(fila, {
        'nombre': 'Vale de hidratación',
        'descripcion': 'Una bebida isotónica en la tienda aliada.',
        'puntos_requeridos': 150,
        'disponible': true,
      });
    });

    test('una recompensa no disponible viaja con disponible en false', () {
      final fila = completo
          .copyWith(disponible: false)
          .aNuevaRecompensa()!
          .aSupabase();

      expect(fila, {
        'nombre': 'Vale de hidratación',
        'descripcion': 'Una bebida isotónica en la tienda aliada.',
        'puntos_requeridos': 150,
        'disponible': false,
      });
    });

    test('los puntos viajan como entero, no como texto', () {
      final fila = completo.aNuevaRecompensa()!.aSupabase();

      expect(fila['puntos_requeridos'], isA<int>());
    });
  });

  group('lectura de una fila de recompensas', () {
    final fila = <String, dynamic>{
      'id': 'recompensa-9',
      'nombre': 'Botella TRAZA',
      'descripcion': 'Botella reutilizable de 750 ml.',
      'puntos_requeridos': 300,
      'disponible': false,
      'fecha_creacion': '2026-10-19T14:00:00+00:00',
    };

    test('se lee completa', () {
      final recompensa = Recompensa.desdeSupabase(fila);

      expect(recompensa.id, 'recompensa-9');
      expect(recompensa.nombre, 'Botella TRAZA');
      expect(recompensa.descripcion, 'Botella reutilizable de 750 ml.');
      expect(recompensa.puntosRequeridos, 300);
      expect(recompensa.disponible, isFalse);
      expect(
        recompensa.fechaCreacion.isAtSameMomentAs(
          DateTime.utc(2026, 10, 19, 14),
        ),
        isTrue,
      );
    });

    test('una fila incompleta falla en vez de inventarse valores', () {
      for (final columna in [
        'id',
        'nombre',
        'descripcion',
        'puntos_requeridos',
        'disponible',
        'fecha_creacion',
      ]) {
        expect(
          () => Recompensa.desdeSupabase({...fila}..remove(columna)),
          throwsFormatException,
          reason: 'sin $columna',
        );
      }
    });

    test('una columna con un tipo inesperado también falla', () {
      expect(
        () => Recompensa.desdeSupabase({...fila, 'puntos_requeridos': 'mil'}),
        throwsFormatException,
      );
      expect(
        () => Recompensa.desdeSupabase({...fila, 'disponible': 'sí'}),
        throwsFormatException,
      );
      expect(
        () => Recompensa.desdeSupabase({...fila, 'fecha_creacion': 'ayer'}),
        throwsFormatException,
      );
    });
  });

  group('cantidad de puntos al cambiarlos (criterio 2 de SCRUM-380)', () {
    test('sin puntos, o con solo espacios, pide cuántos cuesta', () {
      expect(errorDePuntos(''), 'Indica cuántos puntos cuesta.');
      expect(errorDePuntos('  '), 'Indica cuántos puntos cuesta.');
    });

    test('un valor no numérico indica que la cantidad no es válida', () {
      expect(errorDePuntos('abc'), 'Usa solo números enteros.');
      // `int.tryParse` sin base acepta hexadecimal: '0x10' serían 16.
      expect(errorDePuntos('0x10'), 'Usa solo números enteros.');
      expect(const BorradorRecompensa(puntos: '0X1F').puntosRequeridos, isNull);
    });

    test('los decimales tampoco valen', () {
      expect(errorDePuntos('2.5'), 'Usa solo números enteros.');
    });

    test('cero puntos indica que la cantidad no es válida', () {
      expect(errorDePuntos('0'), 'Los puntos deben ser mayores que cero.');
    });

    test('unos puntos negativos indican que la cantidad no es válida', () {
      expect(errorDePuntos('-5'), 'Los puntos deben ser mayores que cero.');
    });

    test('uno más del tope se rechaza, como el check de la tabla', () {
      expect(errorDePuntos('1000001'), 'Máximo 1000000 puntos.');
    });

    test('1, 150 y 1000000 son cantidades válidas (criterio 1 de '
        'SCRUM-380)', () {
      expect(errorDePuntos('1'), isNull);
      expect(errorDePuntos('150'), isNull);
      expect(errorDePuntos('1000000'), isNull);
    });

    test('los espacios de los extremos no cuentan, como al crear', () {
      expect(errorDePuntos(' 200 '), isNull);
    });

    test('es la misma regla del formulario de creación: no hay dos '
        'versiones de qué puntos valen', () {
      for (final texto in [
        '',
        '  ',
        'abc',
        '2.5',
        '0',
        '-5',
        '1',
        '150',
        '1000000',
        '1000001',
        '2147483648',
      ]) {
        expect(
          errorDePuntos(texto),
          BorradorRecompensa(puntos: texto).errores[CampoRecompensa.puntos],
          reason: 'con "$texto"',
        );
      }
    });
  });
}
