import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../models/connection_profile.dart';
import '../providers/ssh_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/history_provider.dart';
import '../providers/connection_provider.dart';
import '../services/ssh_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  final ConnectionProfile profile;

  const TerminalScreen({super.key, required this.profile});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late Terminal terminal;
  final terminalController = TerminalController();
  late final SshEngine _sshEngine;
  bool _isConnected = false;
  String _statusMessage = 'Connecting...';
  double _fontSize = 14.0;
  bool _ctrlActive = false;
  bool _altActive = false;
  
  @override
  void initState() {
    super.initState();
    _sshEngine = ref.read(sshEngineProvider);
    _fontSize = ref.read(settingsProvider).defaultFontSize;
    terminal = Terminal(maxLines: 10000);
    _connectSSH();
  }

  Future<void> _connectSSH() async {
    try {
      terminal.write('Connecting to ${widget.profile.host}:${widget.profile.port}...\r\n');
      
      if (mounted) {
        setState(() {
          _statusMessage = 'Authenticating...';
        });
      }

      await _sshEngine.connect(widget.profile);
      
      if (!mounted) return;

      setState(() {
        _isConnected = true;
        _statusMessage = 'Connected';
      });

      int initialCols = terminal.viewWidth > 0 ? terminal.viewWidth : 80;
      int initialRows = terminal.viewHeight > 0 ? terminal.viewHeight : 24;
      
      final shell = await _sshEngine.startShell(
        widget.profile.id,
        initialCols,
        initialRows,
      );

      // Log into history
      ref.read(historyProvider.notifier).addHistory(widget.profile.id);
      
      // Update local lastConnected for the profile directly
      final updatedProfile = widget.profile.copyWith(lastConnected: DateTime.now());
      ref.read(connectionProfilesProvider.notifier).updateProfile(updatedProfile);

      // Listen for data from the remote server
      // IMPORTANT: utf8.decoder MUST be bound to the stream to maintain state
      // across TCP chunks, otherwise ANSI escape sequences and multibyte chars get corrupted.
      shell.stdout.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((String text) {
        if (mounted) terminal.write(text);
      });

      shell.stderr.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((String text) {
        if (mounted) terminal.write(text);
      });

      // Send local input to the remote server with sticky modifier support
      terminal.onOutput = (String data) {
        if (data.isEmpty) return;
        
        String output = data;
        
        // Only apply modifier logic if it's a single keystroke (not a paste operation)
        if (data.length == 1) {
          if (_ctrlActive) {
            int charCode = data.toUpperCase().codeUnitAt(0);
            if (charCode >= 64 && charCode <= 126) {
              int ctrlCode = charCode & 0x1F;
              output = String.fromCharCode(ctrlCode);
            } else if (data == ' ') {
              output = '\x00'; // CTRL+Space
            }
          }
          if (_altActive) {
            output = '\x1b$output';
          }
          
          if (_ctrlActive || _altActive) {
            setState(() {
              _ctrlActive = false;
              _altActive = false;
            });
          }
        }
        
        shell.write(utf8.encode(output));
      };
      
      // Handle resize (xterm window size changes)
      terminal.onResize = (w, h, pw, ph) {
        shell.resizeTerminal(w, h, pw, ph);
      };

    } catch (e, stackTrace) {
      debugPrint('TERMINAL ERROR: $e');
      debugPrint('TERMINAL STACK: $stackTrace');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _statusMessage = 'Error';
        });
        
        String rawErr = e.toString();
        String userMsg;
        String tipMsg;

        if (rawErr.contains('Connection refused') || rawErr.contains('errno = 111')) {
          userMsg = 'Connection refused by ${widget.profile.host}:${widget.profile.port}';
          tipMsg = 'Check if SSH daemon (sshd) is running on port ${widget.profile.port} and firewall allows incoming connections.';
        } else if (rawErr.contains('timed out') || rawErr.contains('TimeoutException')) {
          userMsg = 'Connection timed out connecting to ${widget.profile.host}:${widget.profile.port}';
          tipMsg = 'Check host IP/domain, server power, and network firewall settings.';
        } else if (rawErr.contains('SSHAuthFailError')) {
          userMsg = 'Authentication failed for user "${widget.profile.username}"';
          tipMsg = 'Verify password or check that public key is added to ~/.ssh/authorized_keys on the remote server.';
        } else {
          userMsg = rawErr.replaceAll('Exception: ', '');
          tipMsg = 'Edit this connection profile in Servers to verify host, port, and credentials.';
        }
        
        terminal.write('\r\n\x1B[1;31mError:\x1B[0m $userMsg\r\n');
        terminal.write('\x1B[1;33mTip:\x1B[0m $tipMsg\r\n\r\n');
      }
    }
  }

  @override
  void dispose() {
    // Correct Riverpod usage: don't use ref.read inside dispose.
    _sshEngine.disconnect(widget.profile.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.terminal, size: 20, color: AppColors.electricCyan),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.profile.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            _buildStatusBadge(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_out, color: AppColors.textDisabled),
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize - 1.0).clamp(8.0, 48.0);
              });
            },
            tooltip: 'Zoom Out',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: AppColors.textDisabled),
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize + 1.0).clamp(8.0, 48.0);
              });
            },
            tooltip: 'Zoom In',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TerminalView(
                terminal,
                controller: terminalController,
                autofocus: true,
                keyboardType: TextInputType.visiblePassword,
                backgroundOpacity: 0.0,
                textStyle: TerminalStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: _fontSize,
                ),
                theme: _buildTerminalTheme(),
              ),
            ),
            _buildMacroKeybar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? AppColors.phosphorGreen : AppColors.softCrimson,
              boxShadow: _isConnected
                  ? [
                      BoxShadow(
                        color: AppColors.phosphorGreen.withValues(alpha: 0.35),
                        blurRadius: 12,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusMessage,
            style: AppTextStyles.labelMedium,
          ),
        ],
      ),
    );
  }

  TerminalTheme _buildTerminalTheme() {
    return TerminalTheme(
      cursor: AppColors.electricCyan,
      selection: AppColors.surfaceHighlightBorder,
      foreground: AppColors.textPrimary,
      background: AppColors.canvasBase,
      black: const Color(0xFF000000),
      red: AppColors.softCrimson,
      green: AppColors.phosphorGreen,
      yellow: AppColors.subtleAmber,
      blue: AppColors.electricCyan,
      magenta: const Color(0xFFFF00FF),
      cyan: const Color(0xFF00FFFF),
      white: const Color(0xFFFFFFFF),
      brightBlack: const Color(0xFF666666),
      brightRed: const Color(0xFFFF0000),
      brightGreen: const Color(0xFF00FF00),
      brightYellow: const Color(0xFFFFFF00),
      brightBlue: const Color(0xFF0000FF),
      brightMagenta: const Color(0xFFFF00FF),
      brightCyan: const Color(0xFF00FFFF),
      brightWhite: const Color(0xFFFFFFFF),
      searchHitBackground: Colors.yellow,
      searchHitBackgroundCurrent: Colors.orange,
      searchHitForeground: Colors.black,
    );
  }

  Widget _buildMacroKeybar() {
    final List<Map<String, dynamic>> keys = [
      {'label': 'ESC', 'seq': '\x1b', 'isMacro': true},
      {'label': 'TAB', 'seq': '\t', 'isMacro': true},
      {'label': 'CTRL', 'isCtrl': true},
      {'label': 'ALT', 'isAlt': true},
      {'label': '↑', 'seq': '\x1b[A', 'isMacro': true},
      {'label': '↓', 'seq': '\x1b[B', 'isMacro': true},
      {'label': '←', 'seq': '\x1b[D', 'isMacro': true},
      {'label': '→', 'seq': '\x1b[C', 'isMacro': true},
      {'label': 'HOME', 'seq': '\x1b[H', 'isMacro': true},
      {'label': 'END', 'seq': '\x1b[F', 'isMacro': true},
      {'label': 'PG UP', 'seq': '\x1b[5~', 'isMacro': true},
      {'label': 'PG DN', 'seq': '\x1b[6~', 'isMacro': true},
      {'label': 'INS', 'seq': '\x1b[2~', 'isMacro': true},
      {'label': 'DEL', 'seq': '\x1b[3~', 'isMacro': true},
      {'label': 'F1', 'seq': '\x1bOP', 'isMacro': true},
      {'label': 'F2', 'seq': '\x1bOQ', 'isMacro': true},
      {'label': 'F3', 'seq': '\x1bOR', 'isMacro': true},
      {'label': 'F4', 'seq': '\x1bOS', 'isMacro': true},
      {'label': 'F5', 'seq': '\x1b[15~', 'isMacro': true},
      {'label': 'F6', 'seq': '\x1b[17~', 'isMacro': true},
      {'label': 'F7', 'seq': '\x1b[18~', 'isMacro': true},
      {'label': 'F8', 'seq': '\x1b[19~', 'isMacro': true},
      {'label': 'F9', 'seq': '\x1b[20~', 'isMacro': true},
      {'label': 'F10', 'seq': '\x1b[21~', 'isMacro': true},
      {'label': 'F11', 'seq': '\x1b[23~', 'isMacro': true},
      {'label': 'F12', 'seq': '\x1b[24~', 'isMacro': true},
    ];
    
    return Container(
      color: AppColors.surface1,
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final k = keys[index];
          final isCtrl = k['isCtrl'] == true;
          final isAlt = k['isAlt'] == true;
          
          bool isActive = false;
          String label = k['label'] as String;
          if (isCtrl) {
            isActive = _ctrlActive;
            if (isActive) label += ' ✓';
          } else if (isAlt) {
            isActive = _altActive;
            if (isActive) label += ' ✓';
          }

          return InkWell(
            onTap: () {
              if (isCtrl) {
                setState(() => _ctrlActive = !_ctrlActive);
              } else if (isAlt) {
                setState(() => _altActive = !_altActive);
              } else if (k['isMacro'] == true) {
                if (_ctrlActive || _altActive) {
                  setState(() {
                    _ctrlActive = false;
                    _altActive = false;
                  });
                }
                final String seq = k['seq'] as String;
                terminal.onOutput?.call(seq);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isActive ? AppColors.electricCyan.withValues(alpha: 0.2) : Colors.transparent,
                border: Border(
                  right: BorderSide(color: AppColors.surfaceBorder, width: 1),
                  bottom: isActive ? const BorderSide(color: AppColors.electricCyan, width: 2) : BorderSide.none,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? AppColors.electricCyan : AppColors.textPrimary,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
