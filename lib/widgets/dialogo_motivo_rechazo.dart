import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/revision_ruta.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';

/// Pide el motivo de un rechazo y lo devuelve ya sin espacios en los
/// extremos, o null si se canceló (SCRUM-330).
///
/// No deja confirmar sin motivo: lo exige el criterio 6 de SCRUM-321, y es lo
/// único que el autor sabrá de por qué no se publicó lo suyo.
Future<String?> pedirMotivoRechazo(
  BuildContext context, {
  required String titulo,
  String aviso = 'El autor verá este motivo en su notificación.',
}) => showDialog<String>(
  context: context,
  builder: (_) => DialogoMotivoRechazo(titulo: titulo, aviso: aviso),
);

class DialogoMotivoRechazo extends StatefulWidget {
  const DialogoMotivoRechazo({
    super.key,
    required this.titulo,
    required this.aviso,
  });

  static const claveMotivo = Key('motivo-rechazo');
  static const claveConfirmar = Key('motivo-rechazo-confirmar');

  final String titulo;
  final String aviso;

  @override
  State<DialogoMotivoRechazo> createState() => _DialogoMotivoRechazoState();
}

class _DialogoMotivoRechazoState extends State<DialogoMotivoRechazo> {
  final _motivo = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    final error = errorDelMotivo(_motivo.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(_motivo.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.aviso,
            style: const TextStyle(fontSize: 13, color: AppColors.ink2),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: DialogoMotivoRechazo.claveMotivo,
            controller: _motivo,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            // El contador avisa del límite; no se corta lo que se escribe
            // para no perder en silencio lo que se pegó.
            maxLength: maxCaracteresMotivoRechazo,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: 'Ej.: El trazado cruza una autopista',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          key: DialogoMotivoRechazo.claveConfirmar,
          onPressed: _confirmar,
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          child: const Text('Rechazar'),
        ),
      ],
    );
  }
}
