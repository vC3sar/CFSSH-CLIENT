import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/host_key_manager.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class HostKeyDialogs {
  static Future<bool> showVerificationDialog(
    BuildContext context,
    WidgetRef ref,
    String host,
    int port,
    String algorithm,
    String sha256Fingerprint,
    String md5Fingerprint,
    bool isChanged,
    String? oldFingerprint,
  ) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _HostKeyVerificationDialog(
          host: host,
          port: port,
          algorithm: algorithm,
          sha256Fingerprint: sha256Fingerprint,
          md5Fingerprint: md5Fingerprint,
          isChanged: isChanged,
          oldFingerprint: oldFingerprint,
          onAccept: () async {
            // Save the key using the provider
            await ref.read(hostKeyManagerProvider).saveTrustedHost(host, port, algorithm, sha256Fingerprint);
            if (context.mounted) Navigator.pop(context, true);
          },
        );
      },
    ) ?? false;
  }
}

class _HostKeyVerificationDialog extends StatefulWidget {
  final String host;
  final int port;
  final String algorithm;
  final String sha256Fingerprint;
  final String md5Fingerprint;
  final bool isChanged;
  final String? oldFingerprint;
  final VoidCallback onAccept;

  const _HostKeyVerificationDialog({
    required this.host,
    required this.port,
    required this.algorithm,
    required this.sha256Fingerprint,
    required this.md5Fingerprint,
    required this.isChanged,
    required this.oldFingerprint,
    required this.onAccept,
  });

  @override
  State<_HostKeyVerificationDialog> createState() => _HostKeyVerificationDialogState();
}

class _HostKeyVerificationDialogState extends State<_HostKeyVerificationDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isChanged) {
      return _buildChangedDialog(context);
    } else {
      return _buildUnknownDialog(context);
    }
  }

  Widget _buildUnknownDialog(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.subtleAmber, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text('Verify Server Identity', style: AppTextStyles.headlineSmall)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The identity of this server has not been verified yet.',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 24),
            _buildInfoRow('Host', '${widget.host}:${widget.port}'),
            _buildInfoRow('Key Type', widget.algorithm),
            const SizedBox(height: 16),
            _buildFingerprintSection(),
            const SizedBox(height: 24),
            Text(
              'The fingerprint uniquely identifies this SSH server. Verify it using a trusted source before accepting it.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.electricCyan,
            foregroundColor: AppColors.canvasBase,
          ),
          onPressed: widget.onAccept,
          child: const Text('Accept & Save'),
        ),
      ],
    );
  }

  Widget _buildChangedDialog(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.softCrimson, width: 2),
      ),
      title: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.softCrimson, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text('Host Key Changed', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.softCrimson))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The server presented a different host key than the one previously saved.',
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Server', '${widget.host}:${widget.port}'),
            _buildInfoRow('Algorithm', widget.algorithm),
            const SizedBox(height: 16),
            Text('Previously trusted:', style: AppTextStyles.labelMedium),
            Text(
              widget.oldFingerprint ?? 'Unknown',
              style: AppTextStyles.bodySmall.copyWith(fontFamily: 'JetBrains Mono', color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Text('Received:', style: AppTextStyles.labelMedium),
            Text(
              widget.sha256Fingerprint,
              style: AppTextStyles.bodySmall.copyWith(fontFamily: 'JetBrains Mono', color: AppColors.softCrimson),
            ),
            const SizedBox(height: 24),
            Text(
              "This can happen after a server reinstallation, SSH configuration change, host key rotation, IP reassignment, or a potential security issue (Man-in-the-Middle attack).\n\nDo not accept the new key unless you have independently verified the server's new fingerprint.",
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (!_showDetails)
          TextButton(
            onPressed: () {
              setState(() {
                _showDetails = true;
              });
            },
            child: const Text('View Details'),
          ),
        if (_showDetails)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.softCrimson),
            onPressed: widget.onAccept,
            child: const Text('Replace Saved Key'),
          ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
          Text(value, style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildFingerprintSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fingerprint', style: AppTextStyles.labelMedium),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.sha256Fingerprint));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Fingerprint copied')),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text('[ Copy ]', style: AppTextStyles.bodySmall.copyWith(color: AppColors.electricCyan)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.sha256Fingerprint,
            style: AppTextStyles.bodySmall.copyWith(fontFamily: 'JetBrains Mono'),
          ),
          if (_showDetails) ...[
            const SizedBox(height: 12),
            Text('MD5', style: AppTextStyles.labelMedium),
            const SizedBox(height: 4),
            Text(
              widget.md5Fingerprint,
              style: AppTextStyles.bodySmall.copyWith(fontFamily: 'JetBrains Mono'),
            ),
          ],
          if (!_showDetails) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _showDetails = true;
                });
              },
              child: Text(
                '[ View full details ]',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.electricCyan),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
