import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_provider.dart';
import '../models/connection_profile.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'terminal_screen.dart';
import '../security/secure_storage.dart';

class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(connectionProfilesProvider);
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final bgImage = isPortrait ? 'assets/background_vertical.png' : 'assets/background_horizontal.png';

    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: const Text('Connection Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New Connection',
            onPressed: () {
              // Show dialog or navigate to create new connection profile
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
            opacity: 0.7, // Increased opacity so the dark image is visible
          ),
        ),
        child: _buildBody(context, ref, provider),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, ConnectionProfileState state) {
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
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.surface1,
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
            title: Text(profile.name, style: AppTextStyles.titleMedium),
            subtitle: Text(
              '${profile.username}@${profile.host}:${profile.port}',
              style: AppTextStyles.monoSmall,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showProfileEditor(context, ref, profile),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TerminalScreen(profile: profile),
                      ),
                    );
                  },
                  child: const Text('Connect'),
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
      builder: (context) {
        return _ProfileEditor(profile: profile, ref: ref);
      },
    );
  }
}

class _ProfileEditor extends StatefulWidget {
  final ConnectionProfile? profile;
  final WidgetRef ref;

  const _ProfileEditor({this.profile, required this.ref});

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '22');
  bool _obscurePassword = true;
  String _authMethod = 'password';

  @override
  void initState() {
    super.initState();
    if (widget.profile != null) {
      _nameController.text = widget.profile!.name;
      _hostController.text = widget.profile!.host;
      _userController.text = widget.profile!.username;
      _portController.text = widget.profile!.port.toString();
      _authMethod = widget.profile!.authMethod;
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

    final newProfile = ConnectionProfile(
      id: id,
      name: name,
      host: host,
      port: port,
      username: user,
      authMethod: _authMethod,
      createdAt: widget.profile?.createdAt ?? DateTime.now(),
      lastConnected: widget.profile?.lastConnected ?? DateTime.now(),
    );

    // Save password asynchronously if provided
    if (pass.isNotEmpty) {
      final secureStorage = SecureStorage();
      await secureStorage.savePassword(id, pass);
    }

    if (widget.profile == null) {
      widget.ref.read(connectionProfilesProvider.notifier).addProfile(newProfile);
    } else {
      widget.ref.read(connectionProfilesProvider.notifier).updateProfile(newProfile);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
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
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
