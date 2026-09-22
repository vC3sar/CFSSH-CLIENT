import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_provider.dart';
import '../providers/keys_provider.dart';
import '../providers/ssh_provider.dart';
import '../services/ssh_engine.dart';
import '../models/connection_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'terminal_screen.dart';
import 'keys_screen.dart';
import '../security/secure_storage.dart';

class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(connectionProfilesProvider);
    final sshEngine = ref.watch(sshEngineProvider);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final bgImage = isPortrait ? 'assets/background_vertical.png' : 'assets/background_horizontal.png';

    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: const Text('Connection Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key, color: AppColors.electricCyan),
            tooltip: 'SSH Keys',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const KeysScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Connection',
            onPressed: () {
              _showProfileEditor(context, ref, null);
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(bgImage),
            fit: BoxFit.cover,
            opacity: 0.7,
          ),
        ),
        child: _buildBody(context, ref, provider, sshEngine),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ConnectionProfileState state, SshEngine sshEngine) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(child: Text('Error: ${state.error}', style: const TextStyle(color: AppColors.softCrimson)));
    }

    final profiles = state.profiles;
    if (profiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dns_outlined, size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text('No saved connections', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () => _showProfileEditor(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Add Server'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.all(16),
      itemCount: profiles.length,
      itemBuilder: (context, index) {
        final profile = profiles[index];
        final status = state.statuses[profile.id] ?? ServerStatus.checking;

        Widget statusIcon;
        switch (status) {
          case ServerStatus.online:
            statusIcon = const Icon(Icons.check_circle, size: 12, color: AppColors.phosphorGreen);
            break;
          case ServerStatus.offline:
            statusIcon = const Icon(Icons.cancel, size: 12, color: AppColors.softCrimson);
            break;
          case ServerStatus.checking:
            statusIcon = const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
            );
            break;
        }

        return Card(
          color: AppColors.surface1, // Provide material color
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.surface2,
                    child: Icon(Icons.computer, color: AppColors.electricCyan),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.surface2,
                        shape: BoxShape.circle,
                      ),
                      child: statusIcon,
                    ),
                  ),
                ],
              ),
            ),
            title: Text(
              profile.name,
              style: AppTextStyles.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${profile.username}@${profile.host}:${profile.port}',
              style: AppTextStyles.monoSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit Server',
                  onPressed: () => _showProfileEditor(context, ref, profile),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TerminalScreen(profile: profile),
                      ),
                    );
                  },
                  child: sshEngine.getSession(profile.id)?.isConnecting == true
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.canvasBase),
                        )
                      : Text(sshEngine.getSession(profile.id)?.isConnected == true ? 'Resume' : 'Connect'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showProfileEditor(BuildContext context, WidgetRef ref, ConnectionProfile? profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (context) {
        return _ProfileEditor(profile: profile, parentRef: ref);
      },
    );
  }
}

class _ProfileEditor extends ConsumerStatefulWidget {
  final ConnectionProfile? profile;
  final WidgetRef parentRef;

  const _ProfileEditor({this.profile, required this.parentRef});

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  bool _obscurePassword = true;
  String _authMethod = 'password';
  String? _selectedKeyId;

  @override
  void initState() {
    super.initState();
    if (widget.profile != null) {
      _nameController.text = widget.profile!.name;
      _hostController.text = widget.profile!.host;
      _userController.text = widget.profile!.username;
      _portController.text = widget.profile!.port.toString();
      _authMethod = widget.profile!.authMethod;
      _selectedKeyId = widget.profile!.privateKeyId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final user = _userController.text.trim();
    final pass = _passwordController.text;
    final portStr = _portController.text.trim();
    
    if (name.isEmpty || host.isEmpty || user.isEmpty || portStr.isEmpty) return;

    final port = int.tryParse(portStr) ?? 22;
    final id = widget.profile?.id ?? DateTime.now().millisecondsSinceEpoch.toString();

    final keysState = ref.read(keysProvider);
    final effectiveKeyId = (_selectedKeyId != null && keysState.keys.any((k) => k.id == _selectedKeyId))
        ? _selectedKeyId
        : (keysState.keys.isNotEmpty ? keysState.keys.first.id : null);

    final newProfile = ConnectionProfile(
      id: id,
      name: name,
      host: host,
      port: port,
      username: user,
      authMethod: _authMethod,
      privateKeyId: _authMethod == 'private_key' ? effectiveKeyId : null,
      createdAt: widget.profile?.createdAt ?? DateTime.now(),
      lastConnected: widget.profile?.lastConnected ?? DateTime.now(),
    );

    // Save password asynchronously if authMethod is password
    if (_authMethod == 'password') {
      final secureStorage = SecureStorage();
      await secureStorage.savePassword(id, pass);
    }

    if (widget.profile == null) {
      widget.parentRef.read(connectionProfilesProvider.notifier).addProfile(newProfile);
    } else {
      widget.parentRef.read(connectionProfilesProvider.notifier).updateProfile(newProfile);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _confirmDelete() async {
    if (widget.profile == null) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('Delete Server'),
        content: Text('Are you sure you want to delete "${widget.profile!.name}"?'),
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
      widget.parentRef.read(connectionProfilesProvider.notifier).deleteProfile(widget.profile!.id);
      if (mounted) {
        Navigator.pop(context); // close bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server deleted'), backgroundColor: AppColors.surfaceBorder),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keysState = ref.watch(keysProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile == null ? 'New Connection' : 'Edit Connection',
              style: AppTextStyles.headlineMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g. Production VPS)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(labelText: 'Host (IP or Domain)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: 'Port', hintText: '22'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _authMethod,
              decoration: const InputDecoration(labelText: 'Authentication Method'),
              dropdownColor: AppColors.surface2,
              items: const [
                DropdownMenuItem(value: 'password', child: Text('Password')),
                DropdownMenuItem(value: 'private_key', child: Text('Private Key')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _authMethod = val);
                }
              },
            ),
            if (_authMethod == 'password') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password', 
                  hintText: 'Leave blank to keep existing',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      color: AppColors.textDisabled,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
              ),
            ] else if (_authMethod == 'private_key') ...[
              const SizedBox(height: 12),
              if (keysState.keys.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    children: [
                      const Text('No SSH Keys available in key manager.'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const KeysScreen()),
                          );
                        },
                        icon: const Icon(Icons.key, color: AppColors.electricCyan),
                        label: const Text('Generate / Import Key', style: TextStyle(color: AppColors.electricCyan)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedKeyId != null && keysState.keys.any((k) => k.id == _selectedKeyId)
                      ? _selectedKeyId
                      : keysState.keys.first.id,
                  decoration: const InputDecoration(labelText: 'Select SSH Key'),
                  dropdownColor: AppColors.surface2,
                  items: keysState.keys.map((key) {
                    return DropdownMenuItem<String>(
                      value: key.id,
                      child: Text('${key.name} (${key.keyType})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => _selectedKeyId = val);
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const KeysScreen()),
                      );
                    },
                    icon: const Icon(Icons.key, size: 16, color: AppColors.electricCyan),
                    label: const Text('Manage Keys', style: TextStyle(color: AppColors.electricCyan, fontSize: 12)),
                  ),
                ),
              ],
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (widget.profile != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.softCrimson,
                        side: const BorderSide(color: AppColors.softCrimson),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _confirmDelete,
                      child: const Text('Delete'),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

