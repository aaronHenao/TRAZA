import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/nuevo_reto.dart';
import '../../models/periodicidad_reto.dart';
import '../../models/reto.dart';
import '../../services/actividad_provider.dart';
import '../../models/tipo_actividad.dart';
import '../../models/vigencia_reto.dart';
import '../../services/reloj_provider.dart';
import '../../services/retos_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../widgets/ancho_contenido.dart';
import '../../widgets/traza_toast.dart';
import '../../widgets/traza_top_bar.dart';

/// Formulario de retos: crea uno nuevo (SCRUM-139) o edita uno publicado
/// (SCRUM-149), con las mismas validaciones (SCRUM-144).
///
/// Al crear, el administrador no escribe las fechas: elige la periodicidad y
/// la vigencia se calcula sola (SCRUM-142). Al editar, lo único que puede
/// mover de la vigencia es el final, y solo hacia adelante.
class FormularioRetoScreen extends ConsumerStatefulWidget {
  const FormularioRetoScreen({this.original, super.key});

  /// El reto que se está editando, o null si se está creando uno.
  ///
  /// De él salen los valores de partida y lo que ya no se puede cambiar.
  final Reto? original;

  bool get editando => original != null;

  static const claveGuardar = Key('reto-guardar');
  static const claveVigencia = Key('reto-vigencia');
  static const claveRecorte = Key('reto-vigencia-recorte');
  static const claveExtender = Key('reto-extender-plazo');

  @override
  ConsumerState<FormularioRetoScreen> createState() =>
      _FormularioRetoScreenState();
}

class _FormularioRetoScreenState extends ConsumerState<FormularioRetoScreen> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _meta = TextEditingController();
  final _xp = TextEditingController();

  PeriodicidadReto? _periodicidad;
  TipoActividad? _tipoActividad;

  /// Hasta cuándo dura. Solo se usa al editar: al crear lo pone la
  /// periodicidad.
  DateTime? _fin;

  /// Los errores solo se pintan después del primer intento de guardar. Marcar
  /// en rojo lo que el administrador todavía no ha llegado a escribir sería
  /// regañarlo por adelantado.
  Map<CampoReto, String> _errores = const {};

  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    if (original == null) return;

    // Editar empieza por lo que ya está publicado: el administrador corrige,
    // no vuelve a escribirlo todo.
    final borrador = BorradorReto.de(original);
    _nombre.text = borrador.nombre;
    _descripcion.text = borrador.descripcion;
    _meta.text = borrador.meta;
    _xp.text = borrador.xp;
    _periodicidad = borrador.periodicidad;
    _tipoActividad = borrador.tipoActividad;
    _fin = borrador.fin;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    _meta.dispose();
    _xp.dispose();
    super.dispose();
  }

  BorradorReto get _borrador => BorradorReto(
    nombre: _nombre.text,
    descripcion: _descripcion.text,
    periodicidad: _periodicidad,
    tipoActividad: _tipoActividad,
    fin: _fin,
    meta: _meta.text,
    xp: _xp.text,
  );

  /// Quita el error de un campo en cuanto se toca, para que el rojo no se
  /// quede puesto mientras el administrador ya lo está corrigiendo.
  void _alEditar(CampoReto campo) {
    if (!_errores.containsKey(campo)) return;
    setState(() => _errores = {..._errores}..remove(campo));
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final original = widget.original;
      final resultado = original == null
          ? await ref.read(creacionRetoProvider).crear(_borrador)
          : await ref.read(edicionRetoProvider).guardar(original, _borrador);
      if (!mounted) return;

      switch (resultado) {
        case RetoCreado():
          // `pop`: la gestión de retos se refresca al recibir el control y lo
          // guardado aparece en el catálogo (criterio 1).
          context.pop();
          mostrarToast(
            context,
            original == null ? 'Reto creado y activo' : 'Cambios guardados',
          );
        case RetoConErrores(:final errores):
          setState(() => _errores = errores);
          mostrarToast(context, 'Revisa los campos marcados');
        case RetoNoGuardado(:final mensaje):
          // Sin tocar lo escrito: se puede reintentar tal cual.
          mostrarToast(context, mensaje);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnchoContenido(
          child: Column(
            children: [
              TrazaTopBar(
                titulo: widget.editando ? 'Editar reto' : 'Nuevo reto',
                onAtras: context.pop,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: [
                    _Campo(
                      etiqueta: 'Nombre',
                      controlador: _nombre,
                      pista: 'Corre 5 km hoy',
                      error: _errores[CampoReto.nombre],
                      maxCaracteres: maxCaracteresNombreReto,
                      onCambio: () => _alEditar(CampoReto.nombre),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Campo(
                      etiqueta: 'Descripción',
                      controlador: _descripcion,
                      pista:
                          'Qué tiene que hacer el corredor y con qué '
                          'condiciones.',
                      error: _errores[CampoReto.descripcion],
                      lineas: 3,
                      onCambio: () => _alEditar(CampoReto.descripcion),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Periodicidad(
                      elegida: _periodicidad,
                      error: _errores[CampoReto.periodicidad],
                      // Al editar se ve, pero no se toca: cambiarla
                      // recalcularía la vigencia de un reto que la gente ya
                      // puede estar cumpliendo.
                      fijo: widget.editando,
                      onElegir: (periodicidad) => setState(() {
                        _periodicidad = periodicidad;
                        _errores = {..._errores}
                          ..remove(CampoReto.periodicidad);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _TipoActividad(
                      elegido: _tipoActividad,
                      error: _errores[CampoReto.tipoActividad],
                      // Igual: el tipo y la periodicidad deciden en qué hueco
                      // cae el reto, y moverlo dejaría a quien lo tenga
                      // activo con dos del mismo.
                      fijo: widget.editando,
                      onElegir: (tipo) => setState(() {
                        _tipoActividad = tipo;
                        _errores = {..._errores}
                          ..remove(CampoReto.tipoActividad);
                      }),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (widget.original case final original?)
                      _VigenciaEditable(
                        original: original,
                        fin: _fin ?? original.vigencia.fin,
                        onExtender: (fecha) => setState(() => _fin = fecha),
                      )
                    else
                      _Vigencia(periodicidad: _periodicidad),
                    const SizedBox(height: AppSpacing.md),
                    _MetaYXp(
                      meta: _Campo(
                        etiqueta: 'Meta',
                        controlador: _meta,
                        pista: '5',
                        sufijo: 'km',
                        error: _errores[CampoReto.meta],
                        teclado: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        // La coma se admite porque el teclado del usuario
                        // puede ofrecerla en vez del punto.
                        formatos: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onCambio: () => _alEditar(CampoReto.meta),
                      ),
                      xp: _Campo(
                        etiqueta: 'XP otorgada',
                        controlador: _xp,
                        pista: '50',
                        sufijo: 'XP',
                        error: _errores[CampoReto.xp],
                        teclado: TextInputType.number,
                        formatos: [FilteringTextInputFormatter.digitsOnly],
                        onCambio: () => _alEditar(CampoReto.xp),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (!widget.editando) const _AvisoActivo(),
                  ],
                ),
              ),
              _PieConBoton(
                guardando: _guardando,
                texto: widget.editando ? 'Guardar cambios' : 'Crear reto',
                onGuardar: _guardando ? null : _guardar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Meta y XP, lado a lado mientras quepan.
///
/// Con la pantalla muy estrecha —o con el texto del sistema en grande— dos
/// campos numéricos con su etiqueta y su posible mensaje de error no caben en
/// una fila sin quedar ilegibles, así que se apilan.
class _MetaYXp extends StatelessWidget {
  const _MetaYXp({required this.meta, required this.xp});

  final Widget meta;
  final Widget xp;

  /// Por debajo de esto cada columna bajaría de unos 140 px, que no alcanzan
  /// para "XP otorgada" y su mensaje de error.
  static const _anchoMinimo = 300.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, restricciones) {
        if (restricciones.maxWidth < _anchoMinimo) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              meta,
              const SizedBox(height: AppSpacing.md),
              xp,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: meta),
            const SizedBox(width: 12),
            Expanded(child: xp),
          ],
        );
      },
    );
  }
}

/// Campo de texto con su etiqueta y, cuando lo hay, su mensaje de error
/// debajo (SCRUM-144).
class _Campo extends StatelessWidget {
  const _Campo({
    required this.etiqueta,
    required this.controlador,
    required this.pista,
    required this.onCambio,
    this.error,
    this.sufijo,
    this.lineas = 1,
    this.maxCaracteres,
    this.teclado,
    this.formatos,
  });

  final String etiqueta;
  final TextEditingController controlador;
  final String pista;
  final VoidCallback onCambio;
  final String? error;
  final String? sufijo;
  final int lineas;
  final int? maxCaracteres;
  final TextInputType? teclado;
  final List<TextInputFormatter>? formatos;

  @override
  Widget build(BuildContext context) {
    final hayError = error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiqueta,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controlador,
          onChanged: (_) => onCambio(),
          maxLines: lineas,
          maxLength: maxCaracteres,
          keyboardType: teclado,
          inputFormatters: formatos,
          decoration: InputDecoration(
            hintText: pista,
            suffixText: sufijo,
            counterText: '',
            filled: hayError,
            fillColor: hayError ? AppColors.dangerTint : null,
            enabledBorder: hayError ? _bordeError : null,
            focusedBorder: hayError ? _bordeError : null,
          ),
        ),
        if (hayError) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  static final _bordeError = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
  );
}

/// Los tres botones de periodicidad (`.segmented` del prototipo).
class _Periodicidad extends StatelessWidget {
  const _Periodicidad({
    required this.elegida,
    required this.onElegir,
    this.error,
    this.fijo = false,
  });

  final PeriodicidadReto? elegida;
  final ValueChanged<PeriodicidadReto> onElegir;
  final String? error;

  /// Se ve, pero no se toca. Al editar, lo que ya está elegido explica el
  /// reto; esconderlo dejaría al administrador sin saber qué está editando.
  final bool fijo;

  static Key claveDe(PeriodicidadReto periodicidad) =>
      Key('periodicidad-${periodicidad.valorDb}');

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EtiquetaCampo(texto: 'Periodicidad', fijo: fijo),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.bgAlt,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: error == null
                ? null
                : Border.all(color: AppColors.danger, width: 1.5),
          ),
          child: Row(
            children: [
              for (final periodicidad in PeriodicidadReto.values)
                // Fijo: solo queda el elegido. Tres botones de los que dos no
                // responden se leen como una pantalla rota.
                if (!fijo || periodicidad == elegida)
                  Expanded(
                    child: _BotonPeriodicidad(
                      key: claveDe(periodicidad),
                      periodicidad: periodicidad,
                      activa: periodicidad == elegida,
                      onTap: fijo ? null : () => onElegir(periodicidad),
                    ),
                  ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}

/// Correr · Trote · Caminar, con la misma forma que la periodicidad: son dos
/// decisiones del mismo tipo, y juntas definen de qué va el reto.
///
/// El administrador crea los retos que quiera de cualquier tipo; el límite de
/// uno por hueco es de quien los activa, no de quien los publica.
class _TipoActividad extends ConsumerWidget {
  const _TipoActividad({
    required this.elegido,
    required this.onElegir,
    this.error,
    this.fijo = false,
  });

  final TipoActividad? elegido;
  final ValueChanged<TipoActividad> onElegir;
  final String? error;

  /// Se ve, pero no se toca. Ver [_Periodicidad.fijo].
  final bool fijo;

  static Key claveDe(String nombre) => Key('tipo-actividad-$nombre');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(tiposActividadProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EtiquetaCampo(texto: 'Tipo de actividad', fijo: fijo),
        const SizedBox(height: 7),
        switch (catalogo) {
          AsyncData(value: final tipos) => Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.bgAlt,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: error == null
                  ? null
                  : Border.all(color: AppColors.danger, width: 1.5),
            ),
            child: Row(
              children: [
                for (final tipo in ordenarTiposActividad(tipos))
                  if (!fijo || tipo == elegido)
                    Expanded(
                      child: _BotonTipo(
                        key: claveDe(tipo.nombre),
                        tipo: tipo,
                        activo: tipo == elegido,
                        onTap: fijo ? null : () => onElegir(tipo),
                      ),
                    ),
              ],
            ),
          ),
          // Sin el catálogo no se puede elegir: los ids vienen de la tabla y
          // son lo que se guarda.
          AsyncError() => const Text(
            'No pudimos cargar los tipos de actividad.',
            style: TextStyle(fontSize: 12, color: AppColors.danger),
          ),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        },
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: const TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}

class _BotonTipo extends StatelessWidget {
  const _BotonTipo({
    required this.tipo,
    required this.activo,
    required this.onTap,
    super.key,
  });

  final TipoActividad tipo;
  final bool activo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: activo ? AppColors.bg : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          tipo.nombre,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: activo ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// La etiqueta de un campo, que dice "No se cambia" cuando no se puede
/// editar.
///
/// El motivo va en la pantalla y no solo en el código: un campo que no
/// responde sin explicar por qué parece averiado.
class _EtiquetaCampo extends StatelessWidget {
  const _EtiquetaCampo({required this.texto, required this.fijo});

  final String texto;
  final bool fijo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Flexible: con el texto del sistema agrandado, en 320 px la etiqueta
        // y su aclaración no caben de lado a lado.
        Flexible(
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
        if (fijo) ...[
          const SizedBox(width: 6),
          const Flexible(
            child: Text(
              '· No se cambia',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
          ),
        ],
      ],
    );
  }
}

/// La vigencia al editar: fija salvo el final, que solo se puede alargar.
class _VigenciaEditable extends ConsumerWidget {
  const _VigenciaEditable({
    required this.original,
    required this.fin,
    required this.onExtender,
  });

  final Reto original;

  /// El final elegido, que de partida es el que ya tenía.
  final DateTime fin;

  final ValueChanged<DateTime> onExtender;

  bool get _extendido => fin.isAfter(original.vigencia.fin);

  Future<void> _elegirFecha(BuildContext context) async {
    // Desde el día siguiente al final actual: acortar el plazo dejaría sin
    // tiempo a quien va cumpliendo el reto, así que no es que esté prohibido,
    // es que el calendario no lo ofrece.
    final primera = original.vigencia.fin.add(const Duration(days: 1));

    final elegida = await showDatePicker(
      context: context,
      // Nunca antes de `primera`: showDatePicker exige que el día en el que
      // abre esté dentro del rango, y el final actual queda justo fuera.
      initialDate: fin.isBefore(primera) ? primera : fin,
      firstDate: primera,
      lastDate: DateTime(original.vigencia.fin.year + 2),
      helpText: 'Hasta cuándo dura el reto',
    );
    if (elegida != null) onExtender(elegida);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      key: FormularioRetoScreen.claveVigencia,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_today_outlined,
                  size: 17,
                  color: AppColors.secondaryDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Del ${_Vigencia.fechaCorta(original.vigencia.inicio)} '
                      'al ${_Vigencia.fechaCorta(fin)}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _extendido
                          ? 'Se guardará con el plazo alargado.'
                          : 'El plazo solo se puede alargar.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.ink2,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: FormularioRetoScreen.claveExtender,
            onPressed: () => _elegirFecha(context),
            icon: const Icon(Icons.more_time, size: 18),
            label: Text(_extendido ? 'Cambiar el plazo' : 'Extender el plazo'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(40),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonPeriodicidad extends StatelessWidget {
  const _BotonPeriodicidad({
    required this.periodicidad,
    required this.activa,
    required this.onTap,
    super.key,
  });

  final PeriodicidadReto periodicidad;
  final bool activa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: activa ? AppColors.bg : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: activa ? AppShadow.card : null,
        ),
        child: Text(
          periodicidad.etiqueta,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: activa ? AppColors.ink : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// La vigencia que le tocará al reto. Es de solo lectura a propósito: la
/// calcula la periodicidad (SCRUM-142) y el administrador no la escribe.
class _Vigencia extends ConsumerWidget {
  const _Vigencia({required this.periodicidad});

  final PeriodicidadReto? periodicidad;

  static const _dias = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];
  static const _meses = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  static String _fecha(DateTime dia) =>
      '${_dias[dia.weekday - 1]} ${dia.day} de ${_meses[dia.month - 1]}';

  /// Sin el día de la semana: al editar se muestran dos fechas seguidas y el
  /// nombre del día las haría ilegibles.
  static String fechaCorta(DateTime dia) =>
      '${dia.day} de ${_meses[dia.month - 1]}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodicidad = this.periodicidad;
    final ahora = ref.read(relojProvider)();

    final (titulo, detalle) = switch (periodicidad) {
      null => (
        'Elige la periodicidad',
        'Se calcula sola: no hay que escribir fechas.',
      ),
      _ => _textoDe(periodicidad, ahora),
    };

    // El período ya venía corriendo: el reto durará menos de lo que sugiere
    // su periodicidad. Se dice antes de guardar, no después.
    final vigencia = periodicidad?.vigenciaDesde(ahora);
    final recorte = vigencia != null && vigencia.empezoAntesDe(ahora)
        ? 'Quedan ${vigencia.diasRestantesDesde(ahora)} de ${vigencia.dias} '
              'días: el período ya empezó.'
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.secondaryTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 17,
              color: AppColors.secondaryDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VIGENCIA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.44,
                    color: AppColors.ink2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  titulo,
                  key: FormularioRetoScreen.claveVigencia,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(fontSize: 12, color: AppColors.ink2),
                ),
                if (recorte != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 13,
                        color: AppColors.accentInk,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          recorte,
                          key: FormularioRetoScreen.claveRecorte,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accentInk,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static (String, String) _textoDe(PeriodicidadReto p, DateTime ahora) {
    final VigenciaReto vigencia = p.vigenciaDesde(ahora);

    return switch (p) {
      PeriodicidadReto.diaria => (
        'Hoy, ${_fecha(vigencia.inicio)}',
        'Termina a medianoche.',
      ),
      PeriodicidadReto.semanal => (
        'Del ${_fecha(vigencia.inicio)} al ${_fecha(vigencia.fin)}',
        'De lunes a domingo.',
      ),
      PeriodicidadReto.mensual => (
        'Del ${_fecha(vigencia.inicio)} al ${_fecha(vigencia.fin)}',
        'Todo el mes en curso.',
      ),
    };
  }
}

/// SCRUM-145: el reto nace activo, y el administrador tiene que saberlo antes
/// de guardar.
class _AvisoActivo extends StatelessWidget {
  const _AvisoActivo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondaryTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: AppColors.secondaryDark,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'El reto queda activo apenas lo guardes y aparece en el '
              'catálogo de los corredores.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.secondaryDark,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PieConBoton extends StatelessWidget {
  const _PieConBoton({
    required this.guardando,
    required this.texto,
    required this.onGuardar,
  });

  final bool guardando;
  final String texto;
  final VoidCallback? onGuardar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        12,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: FilledButton(
        key: FormularioRetoScreen.claveGuardar,
        onPressed: onGuardar,
        // Ancho completo, como el botón principal del prototipo.
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: guardando
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(texto),
      ),
    );
  }
}
