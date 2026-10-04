import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/insignia.dart';
import '../services/insignias_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import 'traza_card.dart';

/// Las insignias del corredor (SCRUM-193, criterio 6).
///
/// Muestra el catálogo completo: las obtenidas con su color y las pendientes
/// en gris con la XP que piden, para que se vea qué viene. Quien las otorga
/// es el trigger de la base; esto solo las lee.
class SeccionInsignias extends ConsumerWidget {
  const SeccionInsignias({super.key});

  static const clave = Key('seccion-insignias');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(insigniasProvider)) {
      // Sin catálogo no hay nada que mostrar ni que prometer.
      AsyncData(value: final insignias) when insignias.isEmpty =>
        const SizedBox.shrink(),
      AsyncData(value: final insignias) => _Catalogo(insignias: insignias),
      // El detalle del error no le sirve al corredor: se avisa y se deja
      // reintentar.
      AsyncError() => _NoSePudoCargar(
        onReintentar: () => ref.invalidate(insigniasProvider),
      ),
      // La progresión ya muestra su propia carga; aquí no hace falta otra.
      _ => const SizedBox.shrink(),
    };
  }
}

class _Catalogo extends StatelessWidget {
  const _Catalogo({required this.insignias});

  final List<Insignia> insignias;

  @override
  Widget build(BuildContext context) {
    final obtenidas = insignias.where((insignia) => insignia.obtenida).length;

    return TrazaCard(
      key: SeccionInsignias.clave,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _Rotulo('INSIGNIAS')),
              _Pastilla(
                texto: '$obtenidas de ${insignias.length}',
                fondo: AppColors.primaryTint,
                color: AppColors.primaryDark,
              ),
            ],
          ),
          for (final insignia in insignias) ...[
            const SizedBox(height: AppSpacing.md),
            _FilaInsignia(
              key: ValueKey('insignia-${insignia.id}'),
              insignia: insignia,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaInsignia extends StatelessWidget {
  const _FilaInsignia({required this.insignia, super.key});

  final Insignia insignia;

  @override
  Widget build(BuildContext context) {
    final obtenida = insignia.obtenida;
    final dibujo = _Dibujo.de(insignia.icono);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: obtenida ? dibujo.fondo : AppColors.bgAlt,
          ),
          child: Icon(
            dibujo.icono,
            size: 22,
            color: obtenida ? dibujo.color : AppColors.ink3,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                insignia.nombre,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: obtenida ? AppColors.ink : AppColors.ink2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                insignia.descripcion,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.ink2,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (obtenida)
          const _Pastilla(
            texto: 'Obtenida',
            fondo: AppColors.accentTint,
            color: AppColors.accentInk,
          )
        else
          _Pastilla(
            texto: '${insignia.xpRequerida} XP',
            fondo: AppColors.bgAlt,
            color: AppColors.ink2,
          ),
      ],
    );
  }
}

/// Icono y colores de cada insignia del catálogo de `0010_insignias.sql`.
///
/// Los colores suben con la dificultad: lima para las primeras, lavanda para
/// las de distancia y morado para las de constancia.
class _Dibujo {
  const _Dibujo(this.icono, this.fondo, this.color);

  final IconData icono;
  final Color fondo;
  final Color color;

  static const _inicial = (AppColors.accentTint, AppColors.accentInk);
  static const _distancia = (AppColors.secondaryTint, AppColors.secondaryDark);
  static const _constancia = (AppColors.primaryTint, AppColors.primaryDark);

  static final _porClave = {
    'huella': _crear(Icons.directions_walk, _inicial),
    'fuego': _crear(Icons.local_fire_department, _inicial),
    'diez': _crear(Icons.directions_run, _inicial),
    'media': _crear(Icons.military_tech, _distancia),
    'maraton': _crear(Icons.emoji_events, _distancia),
    'calle': _crear(Icons.location_city, _distancia),
    'primavera': _crear(Icons.local_florist, _constancia),
    'colombia': _crear(Icons.map, _constancia),
    'leyenda': _crear(Icons.workspace_premium, _constancia),
  };

  /// La base puede traer una insignia nueva antes que la versión de la app
  /// que conoce su icono: se dibuja con uno genérico en vez de fallar.
  static final _generico = _crear(Icons.verified_outlined, _constancia);

  static _Dibujo _crear(IconData icono, (Color, Color) colores) =>
      _Dibujo(icono, colores.$1, colores.$2);

  static _Dibujo de(String clave) => _porClave[clave] ?? _generico;
}

class _NoSePudoCargar extends StatelessWidget {
  const _NoSePudoCargar({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return TrazaCard(
      key: SeccionInsignias.clave,
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 22, color: AppColors.ink3),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'No pudimos cargar tus insignias',
              style: TextStyle(fontSize: 13, color: AppColors.ink2),
            ),
          ),
          TextButton(
            onPressed: onReintentar,
            child: const Text('Volver a intentar'),
          ),
        ],
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  const _Rotulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.66,
        color: AppColors.ink2,
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({
    required this.texto,
    required this.fondo,
    required this.color,
  });

  final String texto;
  final Color fondo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
