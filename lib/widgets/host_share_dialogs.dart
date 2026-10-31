import 'dart:io' show File, Platform;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/connection_profile.dart';
import '../providers/connection_provider.dart';
import '../providers/keys_provider.dart';
import '../security/secure_storage.dart';
import '../services/host_share_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/icon_registry.dart';

class HostShareDialogs {
  HostShareDialogs._();

  static Future<void> showShareHostDialog(
    BuildContext context,
    ConnectionProfile profile,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ShareHostDialog(profile: profile),
    );
  }

  static Future<void> showImportHostDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportHostDialog(parentRef: ref),
    );
  }
}

class _ShareHostDialog extends StatefulWidget {
  final ConnectionProfile profile;

  const _ShareHostDialog({required this.profile});

  @override
  State<_ShareHostDialog> createState() => _ShareHostDialogState();
}

class _ShareHostDialogState extends State<_ShareHostDialog> {
  HostShareBundle? _bundle;
  String? _error;
  bool _isLoading = true;
  bool _isSavingImage = false;
  int _currentStep = 0; // 0 = QR (Paso 1/2), 1 = Frase Secreta (Paso 2/2)

  @override
  void initState() {
    super.initState();
    _generateNewBundle();
  }

  Future<void> _generateNewBundle() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // If there was a previous bundle generated in this dialog session,
      // burn its tokenId so only the newly generated one remains valid.
      if (_bundle != null) {
        await HostShareService.markTokenConsumed(_bundle!.tokenId);
      }
      final bundle = await HostShareService.createShareBundle(widget.profile);
      if (mounted) {
        setState(() {
          _bundle = bundle;
          _isLoading = false;
          _currentStep = 0; // Reset to step 1 on new bundle
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveQrAsPng() async {
    if (_bundle == null || _isSavingImage) return;
    setState(() => _isSavingImage = true);

    try {
      final painter = QrPainter(
        data: _bundle!.qrPayload,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.L,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      );

      const double size = 600.0;
      const double padding = 40.0;
      const double totalSize = size + padding * 2;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, totalSize, totalSize),
        Paint()..color = Colors.white,
      );
      canvas.save();
      canvas.translate(padding, padding);
      painter.paint(canvas, const Size(size, size));
      canvas.restore();

      final picture = recorder.endRecording();
      final img = await picture.toImage(totalSize.toInt(), totalSize.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('No se pudo renderizar la imagen del QR.');
      }
      final pngBytes = byteData.buffer.asUint8List();

      final safeName = widget.profile.name
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_')
          .toLowerCase();

      final saveUri = await FilePicker.saveFile(
        dialogTitle: 'Guardar código QR de uso único',
        fileName: 'cfssh_${safeName}_qr.png',
        type: FileType.custom,
        allowedExtensions: ['png'],
        bytes: pngBytes,
      );

      if (saveUri != null && !kIsWeb) {
        try {
          final filePath = saveUri.toFilePath();
          if (filePath.isNotEmpty) {
            final outFile = File(filePath);
            if (!await outFile.exists()) {
              await outFile.writeAsBytes(pngBytes);
            }
          }
        } catch (_) {
          // On Android/SAF, saveFile already handles writing bytes
        }
      }

      if (mounted && saveUri != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Imagen QR guardada correctamente.'),
            backgroundColor: AppColors.phosphorGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar QR: $e'),
            backgroundColor: AppColors.softCrimson,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      title: Row(
        children: [
          const Icon(IconRegistry.qrShare, color: AppColors.electricCyan, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _currentStep == 0
                  ? 'Compartir Host (Paso 1/2)'
                  : 'Frase Secreta (Paso 2/2)',
              style: AppTextStyles.headlineSmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Cerrar',
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: _isLoading
            ? const SizedBox(
                height: 260,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.electricCyan),
                ),
              )
            : _error != null
                ? _buildErrorState()
                : _buildShareContent(),
      ),
      actions: [
        if (_bundle != null) ...[
          if (_currentStep == 1)
            TextButton.icon(
              onPressed: () {
                setState(() => _currentStep = 0);
              },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: const Text('Volver al QR'),
            )
          else ...[
            TextButton.icon(
              onPressed: _generateNewBundle,
              icon: const Icon(Icons.refresh, size: 16, color: AppColors.electricCyan),
              label: const Text(
                'Regenerar',
                style: TextStyle(color: AppColors.electricCyan),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _isSavingImage ? null : _saveQrAsPng,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Guardar PNG'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.surfaceBorder),
              ),
            ),
          ],
        ],
        if (_currentStep == 0)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.electricCyan,
              foregroundColor: Colors.black,
            ),
            onPressed: _bundle == null
                ? null
                : () {
                    setState(() => _currentStep = 1);
                  },
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text(
              'Siguiente Paso',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          )
        else
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.phosphorGreen,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Finalizar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(IconRegistry.warning, color: AppColors.softCrimson, size: 48),
        const SizedBox(height: 12),
        Text(
          _error ?? 'Error desconocido',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.softCrimson),
        ),
      ],
    );
  }

  Widget _buildShareContent() {
    final bundle = _bundle!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step progress indicator bar
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.electricCyan,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: _currentStep >= 1
                        ? AppColors.phosphorGreen
                        : AppColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 1. SECURITY WARNING BANNER (AVISO DE NO COMPARTIR)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.softCrimson.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.softCrimson.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  IconRegistry.warning,
                  color: AppColors.softCrimson,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVISO DE SEGURIDAD — NO COMPARTIR',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.softCrimson,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Este QR y su frase secreta contienen la credencial (${bundle.authSummary}). Son de USO ÚNICO. No los compartas con terceros.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. HOST & AUTH METHOD SUMMARY
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.surfaceBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns, color: AppColors.electricCyan, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.profile.name,
                        style: AppTextStyles.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${widget.profile.username}@${widget.profile.host}:${widget.profile.port} • ${bundle.authSummary}',
                        style: AppTextStyles.monoSmall.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_currentStep == 0) ...[
            // STEP 1: QR CODE VIEW
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.electricCyan, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.electricCyan.withValues(alpha: 0.18),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: QrImageView(
                  data: bundle.qrPayload,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                  size: 220,
                  gapless: true,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: bundle.qrPayload));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código cifrado copiado al portapapeles'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(IconRegistry.copy, size: 14, color: AppColors.textSecondary),
                label: Text(
                  'Copiar datos cifrados del QR',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.electricCyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Paso 1: Escanea este QR en el otro dispositivo. Luego presiona "Siguiente Paso" para ver la frase de desbloqueo.',
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // STEP 2: ONE-TIME 3-WORD SECRET PHRASE BOX
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.phosphorGreen.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.key,
                        size: 18,
                        color: AppColors.phosphorGreen,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'FRASE SECRETA DE DESBLOQUEO',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.phosphorGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: bundle.words.asMap().entries.map((entry) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.canvasBase,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.phosphorGreen.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Text(
                          entry.value,
                          style: AppTextStyles.monoLarge.copyWith(
                            color: AppColors.phosphorGreen,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Escribe estas 3 palabras a mano en el dispositivo receptor para descifrar el host. Es de USO ÚNICO: una vez ingresada, el QR queda invalidado para siempre.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: bundle.secretPhrase));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Frase secreta copiada al portapapeles'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(IconRegistry.copy, size: 14),
                    label: const Text('Copiar frase (texto)'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImportHostDialog extends StatefulWidget {
  final WidgetRef parentRef;

  const _ImportHostDialog({required this.parentRef});

  @override
  State<_ImportHostDialog> createState() => _ImportHostDialogState();
}

class _ImportHostDialogState extends State<_ImportHostDialog> {
  final TextEditingController _qrPayloadController = TextEditingController();
  final TextEditingController _phraseController = TextEditingController();

  bool _isImporting = false;
  bool _isScanningCamera = false;
  bool _isAlreadyConsumed = false;
  String? _errorMessage;
  String? _detectedTokenId;

  bool get _supportsLiveCamera =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _qrPayloadController.addListener(_onPayloadChanged);
  }

  @override
  void dispose() {
    _qrPayloadController.removeListener(_onPayloadChanged);
    _qrPayloadController.dispose();
    _phraseController.dispose();
    super.dispose();
  }

  Future<void> _onPayloadChanged() async {
    final raw = _qrPayloadController.text.trim();
    final tokenId = HostShareService.extractTokenId(raw);
    if (tokenId == null) {
      if (_detectedTokenId != null || _isAlreadyConsumed) {
        setState(() {
          _detectedTokenId = null;
          _isAlreadyConsumed = false;
        });
      }
      return;
    }

    final consumed = await HostShareService.isTokenConsumed(tokenId);
    if (mounted) {
      setState(() {
        _detectedTokenId = tokenId;
        _isAlreadyConsumed = consumed;
        if (consumed) {
          _errorMessage =
              'Este código QR ya fue utilizado anteriormente (es de uso único).';
        } else {
          _errorMessage = null;
        }
      });
    }
  }

  Future<void> _pickQrImageFile() async {
    setState(() => _errorMessage = null);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );
      if (result.isEmpty) return;

      final picked = result.first;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        throw const HostShareException('No se pudo leer el archivo seleccionado.');
      }

      final qrText = HostShareService.decodeQrFromImageBytes(bytes);
      _qrPayloadController.text = qrText;
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _pasteQrFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      _qrPayloadController.text = text;
    }
  }

  Future<void> _importHost() async {
    final rawPayload = _qrPayloadController.text.trim();
    final phrase = _phraseController.text.trim();

    if (rawPayload.isEmpty) {
      setState(() {
        _errorMessage = 'Escanea o carga primero el código QR del host.';
      });
      return;
    }
    if (phrase.isEmpty) {
      setState(() {
        _errorMessage = 'Escribe la frase secreta de 3 palabras.';
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final result = await HostShareService.decryptAndConsumeShareBundle(
        rawQrPayload: rawPayload,
        userSecretPhrase: phrase,
      );

      var profileToSave = result.profile;

      if (profileToSave.authMethod == 'private_key' &&
          result.sshKeyModel != null &&
          result.privateKeyPem != null) {
        // Check if a key with the same fingerprint already exists locally
        final existingKeys = widget.parentRef.read(keysProvider).keys;
        final duplicate = existingKeys
            .where((k) =>
                k.fingerprint.isNotEmpty &&
                k.fingerprint == result.sshKeyModel!.fingerprint)
            .toList();

        if (duplicate.isNotEmpty) {
          profileToSave = profileToSave.copyWith(privateKeyId: duplicate.first.id);
        } else {
          await widget.parentRef.read(keysProvider.notifier).saveKey(
                keyModel: result.sshKeyModel!,
                privateKeyPem: result.privateKeyPem!,
                passphrase: result.keyPassphrase,
              );
        }
      } else if (profileToSave.authMethod == 'password' &&
          result.password != null) {
        final secureStorage = SecureStorage();
        await secureStorage.savePassword(profileToSave.id, result.password!);
      }

      await widget.parentRef
          .read(connectionProfilesProvider.notifier)
          .addProfile(profileToSave);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Host "${profileToSave.name}" importado con éxito (token de uso único consumido).',
            ),
            backgroundColor: AppColors.phosphorGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      title: Row(
        children: [
          const Icon(IconRegistry.qrScan, color: AppColors.electricCyan, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Importar Host por QR',
              style: AppTextStyles.headlineSmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
            onPressed: _isImporting ? null : () => Navigator.pop(context),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Security notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: AppColors.electricCyan,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Escanea o carga el QR compartido e introduce a mano las 3 palabras secretas de uso único.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // QR Acquisition Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_supportsLiveCamera)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.electricCyan,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        setState(() {
                          _isScanningCamera = !_isScanningCamera;
                        });
                      },
                      icon: Icon(
                        _isScanningCamera ? Icons.videocam_off : Icons.camera_alt,
                        size: 16,
                      ),
                      label: Text(
                        _isScanningCamera ? 'Cerrar Cámara' : 'Escanear con Cámara',
                      ),
                    ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.electricCyan,
                      side: const BorderSide(color: AppColors.electricCyan),
                    ),
                    onPressed: _pickQrImageFile,
                    icon: const Icon(Icons.image_search, size: 16),
                    label: const Text('Cargar Imagen QR'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.surfaceBorder),
                    ),
                    onPressed: _pasteQrFromClipboard,
                    icon: const Icon(IconRegistry.paste, size: 16),
                    label: const Text('Pegar QR'),
                  ),
                ],
              ),

              if (_isScanningCamera && _supportsLiveCamera) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 210,
                    child: MobileScanner(
                      onDetect: (capture) {
                        for (final barcode in capture.barcodes) {
                          final raw = barcode.rawValue;
                          if (raw != null && raw.startsWith('CFSSH1:')) {
                            _qrPayloadController.text = raw;
                            setState(() {
                              _isScanningCamera = false;
                            });
                            break;
                          }
                        }
                      },
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // QR Status / Payload input
              TextField(
                controller: _qrPayloadController,
                maxLines: 2,
                style: AppTextStyles.monoSmall,
                decoration: InputDecoration(
                  labelText: 'Datos del Código QR',
                  hintText: 'CFSSH1:...',
                  suffixIcon: _detectedTokenId != null
                      ? Icon(
                          _isAlreadyConsumed ? Icons.cancel : Icons.check_circle,
                          color: _isAlreadyConsumed
                              ? AppColors.softCrimson
                              : AppColors.phosphorGreen,
                        )
                      : null,
                ),
              ),
              if (_detectedTokenId != null) ...[
                const SizedBox(height: 6),
                Text(
                  _isAlreadyConsumed
                      ? 'Token #$_detectedTokenId: YA UTILIZADO (Uso único agotado)'
                      : 'Token #$_detectedTokenId: Válido y listo para descifrar',
                  style: AppTextStyles.monoSmall.copyWith(
                    fontSize: 11,
                    color: _isAlreadyConsumed
                        ? AppColors.softCrimson
                        : AppColors.phosphorGreen,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // 3-Word Secret Phrase Input
              TextField(
                controller: _phraseController,
                autocorrect: false,
                enableSuggestions: false,
                style: AppTextStyles.monoMedium.copyWith(
                  color: AppColors.phosphorGreen,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  labelText: 'Frase Secreta de Uso Único (máx. 3 palabras)',
                  hintText: 'Ej: sol mar luz',
                  prefixIcon: Icon(Icons.key, color: AppColors.electricCyan),
                ),
                onSubmitted: (_) => _importHost(),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.softCrimson.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.softCrimson),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        IconRegistry.warning,
                        color: AppColors.softCrimson,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.softCrimson,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.electricCyan,
            foregroundColor: Colors.black,
          ),
          onPressed: (_isImporting || _isAlreadyConsumed) ? null : _importHost,
          icon: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(Icons.lock_open, size: 16),
          label: const Text(
            'Descifrar e Importar',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
