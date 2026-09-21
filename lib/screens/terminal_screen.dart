import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import '../models/connection_profile.dart';
import '../providers/ssh_provider.dart';
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
  
  @override
  void initState() {
    super.initState();
    _sshEngine = ref.read(sshEngineProvider);
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

      // Listen for data from the remote server
      // IMPORTANT: utf8.decoder MUST be bound to the stream to maintain state
      // across TCP chunks, otherwise ANSI escape sequences and multibyte chars get corrupted.
      shell.stdout.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((String text) {
        if (mounted) terminal.write(text);
      });

      shell.stderr.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((String text) {
        if (mounted) terminal.write(text);
      });

      // Send local input to the remote server
      terminal.onOutput = (String data) {
        shell.write(utf8.encode(data));
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
        
        String userMsg = e.toString();
        if (userMsg.contains('SSHAuthFailError')) {
          userMsg = 'Authentication failed. Check username, password or SSH key.';
        } else if (userMsg.contains('SocketException')) {
          userMsg = 'Network error. Host unreachable or connection refused.';
        }
        
        terminal.write('\r\n\x1B[1;31mError:\x1B[0m $userMsg\r\n');
        terminal.write('\r\n\x1B[1;33mStackTrace:\x1B[0m\r\n$stackTrace\r\n');
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
            Text(widget.profile.name),
            const SizedBox(width: 16),
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
    final Map<String, String> keys = {
      'ESC': '\x1b',
      'CTRL+C': '\x03',
      'TAB': '\t',
      '|': '|',
      '/': '/',
      '-': '-',
      '↑': '\x1b[A',
      '↓': '\x1b[B',
      '←': '\x1b[D',
      '→': '\x1b[C',
    };
    
    return Container(
      color: AppColors.surface1,
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        itemBuilder: (context, index) {
          String label = keys.keys.elementAt(index);
          String ansi = keys.values.elementAt(index);
          
          return InkWell(
            onTap: () {
              if (_isConnected) {
                // Manually inject the sequence into the remote shell via xterm's handler
                terminal.onOutput?.call(ansi);
              }
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(
                  right: BorderSide(color: AppColors.surfaceBorder, width: 1),
                ),
              ),
              child: Text(
                label,
                style: AppTextStyles.monoMedium.copyWith(color: AppColors.textPrimary),
              ),
            ),
          );
        },
      ),
    );
  }
}
