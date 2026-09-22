import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../models/trusted_host.dart';
import '../services/host_key_manager.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class TrustedHostsScreen extends ConsumerStatefulWidget {
  const TrustedHostsScreen({super.key});

  @override
  ConsumerState<TrustedHostsScreen> createState() => _TrustedHostsScreenState();
}

class _TrustedHostsScreenState extends ConsumerState<TrustedHostsScreen> {
  late Future<List<TrustedHost>> _hostsFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadHosts();
  }

  void _loadHosts() {
    _hostsFuture = ref.read(hostKeyManagerProvider).getAllTrustedHosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: const Text('SSH Host Keys'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by host or fingerprint...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface1,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<TrustedHost>>(
              future: _hostsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error loading hosts: ${snapshot.error}', style: const TextStyle(color: AppColors.softCrimson)));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No trusted hosts saved yet.', style: TextStyle(color: AppColors.textSecondary)));
                }

                final hosts = snapshot.data!.where((h) {
                  return h.host.toLowerCase().contains(_searchQuery) ||
                         h.fingerprint.toLowerCase().contains(_searchQuery);
                }).toList();

                if (hosts.isEmpty) {
                  return const Center(child: Text('No matching hosts found.', style: TextStyle(color: AppColors.textSecondary)));
                }

                return ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: hosts.length,
                  itemBuilder: (context, index) {
                    final host = hosts[index];
                    return _buildHostCard(host);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostCard(TrustedHost host) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.verified_user, color: AppColors.phosphorGreen),
        title: Text('${host.host}:${host.port}', style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(host.algorithm, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Fingerprint', style: AppTextStyles.labelMedium),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: host.fingerprint));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Fingerprint copied')),
                        );
                      },
                      child: Text('[ Copy ]', style: AppTextStyles.bodySmall.copyWith(color: AppColors.electricCyan)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  host.fingerprint,
                  style: AppTextStyles.bodySmall.copyWith(fontFamily: 'JetBrains Mono', color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('First trusted', style: AppTextStyles.labelMedium),
                        Text(timeago.format(host.createdAt), style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Last used', style: AppTextStyles.labelMedium),
                        Text(timeago.format(host.lastUsedAt), style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.softCrimson),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Revoke Trust'),
                    onPressed: () => _revokeTrust(host),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeTrust(TrustedHost host) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('Revoke Trust'),
        content: Text('Are you sure you want to delete the trusted host key for ${host.host}? You will be prompted to verify it again on the next connection.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.softCrimson),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(hostKeyManagerProvider).deleteTrustedHost(host.id);
      setState(() {
        _loadHosts();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Trust revoked for ${host.host}')),
        );
      }
    }
  }
}
