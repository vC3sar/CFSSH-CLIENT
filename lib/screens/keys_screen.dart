import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../models/ssh_key_model.dart';
import '../providers/keys_provider.dart';
import '../services/key_generator_service.dart';

class KeysScreen extends ConsumerStatefulWidget {
  const KeysScreen({super.key});

  @override
  ConsumerState<KeysScreen> createState() => _KeysScreenState();
}

class _KeysScreenState extends ConsumerState<KeysScreen> {
  @override
  Widget build(BuildContext context) {
    final keysState = ref.watch(keysProvider);

    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        backgroundColor: AppColors.surface1,
        elevation: 0,
        title: const Text('SSH Key Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.electricCyan),
            tooltip: 'Add Key',
            onPressed: () => _showAddKeyOptions(context),
          ),
        ],
      ),
      body: SafeArea(
        child: keysState.isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.electricCyan))
            : keysState.keys.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    padding: const EdgeInsets.all(16.0),
                    itemCount: keysState.keys.length,
                    itemBuilder: (context, index) {
                      final key = keysState.keys[index];
                      return _buildKeyCard(key);
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddKeyOptions(context),
        backgroundColor: AppColors.electricCyan,
        icon: const Icon(Icons.key, color: Colors.black),
        label: const Text('New Key', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.vpn_key_outlined, size: 72, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text('No SSH Keys Found', style: AppTextStyles.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Generate or import SSH keys to securely authenticate with your servers without passwords.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showAddKeyOptions(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Key'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.electricCyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyCard(SshKeyModel key) {
    Color badgeColor = AppColors.electricCyan;
    if (key.keyType.contains('RSA')) badgeColor = Colors.orangeAccent;
    if (key.keyType.contains('ECDSA')) badgeColor = Colors.purpleAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  key.keyType,
                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  key.name,
                  style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                color: AppColors.surface2,
                onSelected: (val) => _handleKeyMenuAction(val, key),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'copy_pub',
                    child: Row(
                      children: [
                        Icon(Icons.copy, size: 18, color: AppColors.electricCyan),
                        SizedBox(width: 8),
                        Text('Copy Public Key'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy_auth_keys',
                    child: Row(
                      children: [
                        Icon(Icons.terminal, size: 18, color: AppColors.phosphorGreen),
                        SizedBox(width: 8),
                        Text('Copy authorized_keys Cmd'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'export_priv',
                    child: Row(
                      children: [
                        Icon(Icons.download, size: 18, color: Colors.amberAccent),
                        SizedBox(width: 8),
                        Text('Export Private Key'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: AppColors.softCrimson),
                        SizedBox(width: 8),
                        Text('Delete Key', style: TextStyle(color: AppColors.softCrimson)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fingerprint Row
          Text('FINGERPRINT', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textDisabled, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            key.fingerprint,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // Action Buttons Bar
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copyToClipboard(key.publicKey, 'Public Key copied to clipboard'),
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy PubKey', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.electricCyan,
                    side: const BorderSide(color: AppColors.surfaceBorder),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final cmd = KeyGeneratorService.generateAuthorizedKeysCommand(key.publicKey);
                    _copyToClipboard(cmd, 'Linux setup command copied to clipboard');
                  },
                  icon: const Icon(Icons.terminal, size: 14),
                  label: const Text('Linux Setup', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.phosphorGreen,
                    side: const BorderSide(color: AppColors.surfaceBorder),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddKeyOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add SSH Key', style: AppTextStyles.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to add an SSH key pair to CFSSH Client.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surface2,
                  child: Icon(Icons.auto_fix_high, color: AppColors.electricCyan),
                ),
                title: const Text('Generate New Key Pair'),
                subtitle: const Text('Create modern Ed25519, RSA, or ECDSA keys instantly'),
                onTap: () {
                  Navigator.pop(context);
                  _showGenerateKeyDialog(context);
                },
              ),
              const Divider(color: AppColors.surfaceBorder),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.surface2,
                  child: Icon(Icons.file_upload_outlined, color: AppColors.phosphorGreen),
                ),
                title: const Text('Import Existing Key'),
                subtitle: const Text('Import PEM file or paste private key text'),
                onTap: () {
                  Navigator.pop(context);
                  _showImportKeyDialog(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showGenerateKeyDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: 'My Ed25519 Key');
    final commentCtrl = TextEditingController(text: 'cfssh-user');
    bool isGenerating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: AppColors.surface1,
              title: const Text('Generate SSH Key Pair'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Key Friendly Name',
                        hintText: 'e.g. Production Server Key',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security, color: AppColors.electricCyan, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Will generate a modern, secure Ed25519 key pair without passphrase.',
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: commentCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Key Comment / Email',
                        hintText: 'e.g. user@cfssh',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isGenerating ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.electricCyan, foregroundColor: Colors.black),
                  onPressed: isGenerating
                      ? null
                      : () async {
                          if (nameCtrl.text.trim().isEmpty) return;
                          setModalState(() => isGenerating = true);
                          try {
                            final generated = await KeyGeneratorService.generateKey(
                              keyType: 'ED25519',
                              comment: commentCtrl.text.trim(),
                            );

                            final keyModel = SshKeyModel(
                              id: const Uuid().v4(),
                              name: nameCtrl.text.trim(),
                              keyType: generated.keyType,
                              publicKey: generated.publicKeyOpenSSH,
                              fingerprint: generated.fingerprint,
                              createdAt: DateTime.now(),
                            );

                            await ref.read(keysProvider.notifier).saveKey(
                                  keyModel: keyModel,
                                  privateKeyPem: generated.privateKeyPem,
                                  passphrase: null,
                                );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('SSH Key Pair generated successfully!'),
                                  backgroundColor: AppColors.phosphorGreen,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => isGenerating = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error generating key: $e'), backgroundColor: AppColors.softCrimson),
                              );
                            }
                          }
                        },
                  child: isGenerating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Generate Key'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showImportKeyDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final keyContentCtrl = TextEditingController();
    final passphraseCtrl = TextEditingController();
    bool isImporting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: AppColors.surface1,
              title: const Text('Import SSH Private Key'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Key Friendly Name',
                        hintText: 'e.g. Imported Laptop Key',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.pickFiles();
                        if (result.isNotEmpty && result.first.path != null) {
                          final file = File(result.first.path!);
                          final content = await file.readAsString();
                          keyContentCtrl.text = content;
                          if (nameCtrl.text.isEmpty) {
                            nameCtrl.text = result.first.name;
                          }
                          setModalState(() {});
                        }
                      },
                      icon: const Icon(Icons.file_open),
                      label: const Text('Pick Private Key File'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.electricCyan,
                        side: const BorderSide(color: AppColors.surfaceBorder),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyContentCtrl,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Private Key Text (PEM / OpenSSH)',
                        hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passphraseCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Key Passphrase (if encrypted)',
                        hintText: 'Optional',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isImporting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.electricCyan, foregroundColor: Colors.black),
                  onPressed: isImporting
                      ? null
                      : () async {
                          final text = keyContentCtrl.text.trim();
                          final name = nameCtrl.text.trim();
                          if (text.isEmpty || name.isEmpty) return;

                          setModalState(() => isImporting = true);
                          try {
                            final parsed = KeyGeneratorService.parsePrivateKey(
                              text,
                              passphrase: passphraseCtrl.text.isNotEmpty ? passphraseCtrl.text : null,
                              comment: name,
                            );

                            final keyModel = SshKeyModel(
                              id: const Uuid().v4(),
                              name: name,
                              keyType: parsed.keyType,
                              publicKey: parsed.publicKeyOpenSSH,
                              fingerprint: parsed.fingerprint,
                              createdAt: DateTime.now(),
                            );

                            await ref.read(keysProvider.notifier).saveKey(
                                  keyModel: keyModel,
                                  privateKeyPem: parsed.privateKeyPem,
                                  passphrase: passphraseCtrl.text.isNotEmpty ? passphraseCtrl.text : null,
                                );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('SSH Key imported successfully!'),
                                  backgroundColor: AppColors.phosphorGreen,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => isImporting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Import failed: $e'), backgroundColor: AppColors.softCrimson),
                              );
                            }
                          }
                        },
                  child: isImporting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Import Key'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleKeyMenuAction(String action, SshKeyModel key) async {
    if (action == 'copy_pub') {
      _copyToClipboard(key.publicKey, 'Public Key copied to clipboard');
    } else if (action == 'copy_auth_keys') {
      final cmd = KeyGeneratorService.generateAuthorizedKeysCommand(key.publicKey);
      _copyToClipboard(cmd, 'Linux setup command copied to clipboard');
    } else if (action == 'export_priv') {
      final privateKeyPem = await ref.read(keysProvider.notifier).getPrivateKeyPem(key.id);
      if (privateKeyPem != null && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface1,
            title: const Text('Export Private Key'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 48),
                  const SizedBox(height: 8),
                  const Text('Keep your private key confidential. Anyone with this key can access servers configured with it.'),
                  const SizedBox(height: 16),
                  SelectableText(
                    privateKeyPem,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: privateKeyPem));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Private Key copied to clipboard!'), backgroundColor: Colors.amberAccent),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy Private Key'),
              ),
            ],
          ),
        );
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface1,
          title: const Text('Delete SSH Key'),
          content: Text('Are you sure you want to delete "${key.name}"? Server connections using this key may fail.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.softCrimson),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await ref.read(keysProvider.notifier).deleteKey(key.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Key deleted.'), backgroundColor: AppColors.surfaceBorder),
          );
        }
      }
    }
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.electricCyan),
    );
  }
}
