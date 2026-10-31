import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show max, min;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/host_key_dialogs.dart';
import '../widgets/resizable_split.dart';
import '../theme/icon_registry.dart';
import '../services/command_dictionary.dart';
import 'sftp_screen.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  final ConnectionProfile profile;

  const TerminalScreen({super.key, required this.profile});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  late Terminal terminal;
  final GlobalKey<TerminalViewState> _terminalViewKey =
      GlobalKey<TerminalViewState>();
  final TerminalController terminalController = TerminalController(
    pointerInputs: const PointerInputs.all(),
  );
  final ScrollController _scrollController = ScrollController();
  final FocusNode _terminalFocusNode = FocusNode();

  Timer? _resizeTimer;
  Timer? _keyRepeatTimer;
  late final SshEngine _sshEngine;

  bool _isConnected = false;
  String _statusMessage = 'Connecting...';
  double _fontSize = 14.0;
  bool _ctrlActive = false;
  bool _altActive = false;
  late bool _showMacroBar;
  bool _showSftp = false;
  bool _showCursorPad = false;
  bool _hasSelection = false;
  bool _hadSelectionOnPointerDown = false;
  bool _showScrollToBottom = false;

  Offset _cursorPadOffset = const Offset(16, 72);

  // Touch horizontal swipe cursor movement state
  int? _activeTouchPointer;
  Offset? _touchStartPos;
  double _touchAccumX = 0.0;
  bool _isTouchHorizontalSwipe = false;
  bool _isTouchVerticalScroll = false;

  // 2D Trackpad accumulator state
  double _trackpadAccumX = 0.0;
  double _trackpadAccumY = 0.0;

  // Double-tab autocomplete state
  DateTime? _lastTabPressTime;
  List<String> _autocompleteSuggestions = [];
  String _activeAutocompletePrefix = '';

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _showMacroBar = kIsWeb || !_isDesktop;
    _sshEngine = ref.read(sshEngineProvider);
    _fontSize = ref.read(settingsProvider).defaultFontSize;

    terminalController.addListener(_onControllerChanged);
    _scrollController.addListener(_onScrollChanged);
    _sshEngine.addListener(_onSshEngineChanged);

    // Ensure the session state exists and grab its persistent terminal
    final session = _sshEngine.getOrCreateSession(widget.profile);
    terminal = session.terminal;

    if (session.isConnected || session.isConnecting) {
      _isConnected = session.isConnected;
      _statusMessage = _isConnected
          ? 'Connected'
          : (session.error != null ? 'Error' : 'Connecting...');

      // Reattach input listener for this new view instance
      _attachInputListener();

      // Ensure the shell is resized and active
      _connectSSH(isReconnecting: true);
    } else {
      _connectSSH(isReconnecting: false);
    }
  }

  void _onControllerChanged() {
    final hasSel = terminalController.selection != null;
    if (hasSel != _hasSelection && mounted) {
      setState(() {
        _hasSelection = hasSel;
      });
    }
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final shouldShow =
        pos.hasContentDimensions && (pos.maxScrollExtent - pos.pixels) > 48.0;
    if (shouldShow != _showScrollToBottom && mounted) {
      setState(() {
        _showScrollToBottom = shouldShow;
      });
    }
  }

  void _onSshEngineChanged() {
    if (!mounted) return;
    final session = _sshEngine.getSession(widget.profile.id);
    if (session == null) return;

    final connected = session.isConnected;
    String status;
    if (session.status == SshSessionStatus.connected) {
      status = 'Connected';
    } else if (session.status == SshSessionStatus.reconnecting) {
      status = 'Reconnecting...';
    } else if (session.status == SshSessionStatus.connecting) {
      status = 'Connecting...';
    } else if (session.status == SshSessionStatus.error) {
      status = 'Error';
    } else {
      status = 'Disconnected';
    }

    if (connected != _isConnected || status != _statusMessage) {
      setState(() {
        _isConnected = connected;
        _statusMessage = status;
      });
    }
  }

  void _attachInputListener() {
    terminal.onOutput = (String data) {
      if (data.isEmpty) return;

      String output = data;

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

      _writeRawToShell(output);
    };
  }

  void _writeRawToShell(String data) {
    if (data.isEmpty) return;
    final currentShell = _sshEngine.getSession(widget.profile.id)?.shell;
    currentShell?.write(utf8.encode(data));
  }

  Future<void> _connectSSH({required bool isReconnecting}) async {
    try {
      if (!isReconnecting) {
        terminal.write(
            'Connecting to ${widget.profile.host}:${widget.profile.port}...\r\n');
        terminal.write(
            'Authenticating (this may freeze the screen for a few seconds)...\r\n');
        if (mounted) {
          setState(() {
            _statusMessage = 'Authenticating...';
          });
        }
      }

      await _sshEngine.connect(
        widget.profile,
        onHostKeyVerification: (host, port, algorithm, sha256Fingerprint,
            md5Fingerprint, isChanged, oldFingerprint) async {
          return await HostKeyDialogs.showVerificationDialog(
            context,
            ref,
            host,
            port,
            algorithm,
            sha256Fingerprint,
            md5Fingerprint,
            isChanged,
            oldFingerprint,
          );
        },
      );

      if (!mounted) return;

      final sessionState = _sshEngine.getSession(widget.profile.id);
      if (sessionState == null || !sessionState.isConnected) {
        throw Exception(sessionState?.error ?? 'Connection failed');
      }

      setState(() {
        _isConnected = true;
        _statusMessage = 'Connected';
      });

      // Assign onResize early so any layout changes are captured
      terminal.onResize = (w, h, pw, ph) {
        if (w > 0 && h > 0) {
          _resizeTimer?.cancel();
          _resizeTimer = Timer(const Duration(milliseconds: 250), () {
            if (mounted) {
              final s = _sshEngine.getSession(widget.profile.id)?.shell;
              s?.resizeTerminal(w, h, pw, ph);
            }
          });
        }
      };

      int initialCols = terminal.viewWidth > 0 ? terminal.viewWidth : 80;
      int initialRows = terminal.viewHeight > 0 ? terminal.viewHeight : 24;

      final shell = await _sshEngine.startShell(
        widget.profile.id,
        initialCols,
        initialRows,
      );

      // In case the terminal layout completed while we were authenticating
      if (terminal.viewWidth > 0 && terminal.viewHeight > 0) {
        shell.resizeTerminal(terminal.viewWidth, terminal.viewHeight, 0, 0);
      }

      // Log into history
      ref.read(historyProvider.notifier).addHistory(widget.profile.id);

      // Update local lastConnected for the profile directly
      final updatedProfile =
          widget.profile.copyWith(lastConnected: DateTime.now());
      ref
          .read(connectionProfilesProvider.notifier)
          .updateProfile(updatedProfile);

      // Setup input listening
      _attachInputListener();
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

        if (rawErr.contains('Connection refused') ||
            rawErr.contains('errno = 111')) {
          userMsg =
              'Connection refused by ${widget.profile.host}:${widget.profile.port}';
          tipMsg =
              'Check if SSH daemon (sshd) is running on port ${widget.profile.port} and firewall allows incoming connections.';
        } else if (rawErr.contains('timed out') ||
            rawErr.contains('TimeoutException')) {
          userMsg =
              'Connection timed out connecting to ${widget.profile.host}:${widget.profile.port}';
          tipMsg =
              'Check host IP/domain, server power, and network firewall settings.';
        } else if (rawErr.contains('SSHAuthFailError') ||
            rawErr.contains('Authentication failed')) {
          userMsg =
              'Authentication failed for user "${widget.profile.username}"';
          tipMsg =
              'Verify password or check that public key is added to ~/.ssh/authorized_keys on the remote server.';
        } else {
          userMsg = rawErr.replaceAll('Exception: ', '');
          tipMsg =
              'Edit this connection profile in Servers to verify host, port, and credentials.';
        }

        terminal.write('\r\n\x1B[1;31mError:\x1B[0m $userMsg\r\n');
        terminal.write('\x1B[1;33mTip:\x1B[0m $tipMsg\r\n\r\n');
      }
    }
  }

  @override
  void dispose() {
    _stopKeyRepeat();
    _resizeTimer?.cancel();
    terminal.onOutput = null;
    terminal.onResize = null;
    terminalController.removeListener(_onControllerChanged);
    terminalController.dispose();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _sshEngine.removeListener(_onSshEngineChanged);
    _terminalFocusNode.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CLIPBOARD OPERATIONS: COPY, PASTE, CUT, SELECT ALL
  // ─────────────────────────────────────────────────────────────────────────

  Future<bool> _copySelection({bool clearAfterCopy = false}) async {
    final selection = terminalController.selection;
    if (selection == null) return false;

    final text = terminal.buffer.getText(selection);
    if (text.isEmpty) return false;

    await Clipboard.setData(ClipboardData(text: text));
    if (clearAfterCopy) {
      terminalController.clearSelection();
    }
    _showQuickFeedback('Copied to clipboard');
    return true;
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      terminal.paste(text);
      terminalController.clearSelection();
      _scrollToBottom();
    }
  }

  Future<bool> _cutSelection({bool cutLineIfNoSelection = false}) async {
    final selection = terminalController.selection;

    if (selection != null) {
      final range = selection.normalized;
      final text = terminal.buffer.getText(range);
      if (text.isEmpty) {
        terminalController.clearSelection();
        return false;
      }

      await Clipboard.setData(ClipboardData(text: text));

      // Check if the selection lies within the currently editable command line
      final deletedFromPrompt = _tryDeleteSelectionFromActiveCommand(range);
      terminalController.clearSelection();

      _showQuickFeedback(
        deletedFromPrompt
            ? 'Cut from command line'
            : 'Copied to clipboard (output is read-only)',
      );
      return true;
    } else if (cutLineIfNoSelection) {
      // Cut the entire active command line if no text is explicitly selected
      final promptBounds = _getActivePromptBounds();
      final curY = terminal.buffer.absoluteCursorY;
      final promptStartY = promptBounds.$1;
      final promptEndY = promptBounds.$2;
      final firstLine = terminal.buffer.lines[promptStartY];
      final prefixEnd = _detectPromptPrefixEnd(
        firstLine,
        curY == promptStartY ? terminal.buffer.cursorX : firstLine.length,
      );

      final range = BufferRangeLine(
        CellOffset(prefixEnd, promptStartY),
        CellOffset(
          terminal.buffer.lines[promptEndY].getTrimmedLength(),
          promptEndY,
        ),
      );
      final cmdText = terminal.buffer.getText(range).trimRight();
      if (cmdText.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: cmdText));
      }
      // Move to end of line (Ctrl+E) and kill line backward (Ctrl+U)
      _writeRawToShell('\x05\x15');
      _showQuickFeedback('Line cut to clipboard');
      return true;
    }

    return false;
  }

  /// If [range] is inside the current active command prompt in the main buffer,
  /// moves the cursor to the end of [range] and sends backspaces to delete it.
  bool _tryDeleteSelectionFromActiveCommand(BufferRange range) {
    if (!_isConnected || terminal.isUsingAltBuffer) return false;

    final normalized = range.normalized;
    final (promptStartY, promptEndY) = _getActivePromptBounds();

    if (normalized.begin.y < promptStartY || normalized.end.y > promptEndY) {
      return false;
    }

    final firstLine = terminal.buffer.lines[promptStartY];
    final curY = terminal.buffer.absoluteCursorY;
    final curX = terminal.buffer.cursorX;
    final prefixEnd = _detectPromptPrefixEnd(
      firstLine,
      curY == promptStartY ? curX : firstLine.length,
    );

    // Ensure selection starts at or after the shell prompt prefix
    final effectiveStartX = normalized.begin.y == promptStartY
        ? max(normalized.begin.x, prefixEnd)
        : normalized.begin.x;

    final lastLineLen = max(
      terminal.buffer.lines[promptEndY].getTrimmedLength(),
      curY == promptEndY ? curX : 0,
    );
    final effectiveEndX = normalized.end.y == promptEndY
        ? min(normalized.end.x, lastLineLen)
        : min(normalized.end.x, terminal.viewWidth);

    final startLinear =
        (normalized.begin.y - promptStartY) * terminal.viewWidth +
            effectiveStartX;
    final endLinear =
        (normalized.end.y - promptStartY) * terminal.viewWidth + effectiveEndX;
    final curLinear = (curY - promptStartY) * terminal.viewWidth + curX;

    final deleteCount = endLinear - startLinear;
    if (deleteCount <= 0) return false;

    final moveDelta = endLinear - curLinear;
    final buffer = StringBuffer();

    if (moveDelta < 0) {
      final leftSeq = terminal.cursorKeysMode ? '\x1bOD' : '\x1b[D';
      for (int i = 0; i < -moveDelta; i++) {
        buffer.write(leftSeq);
      }
    } else if (moveDelta > 0) {
      final rightSeq = terminal.cursorKeysMode ? '\x1bOC' : '\x1b[C';
      for (int i = 0; i < moveDelta; i++) {
        buffer.write(rightSeq);
      }
    }

    // Send Backspace (0x7F) for each character in the selected range
    for (int i = 0; i < deleteCount; i++) {
      buffer.write('\x7f');
    }

    _writeRawToShell(buffer.toString());
    return true;
  }

  void _selectAll() {
    if (terminal.buffer.lines.length == 0) return;

    int firstNonEmpty = 0;
    int lastNonEmpty = terminal.buffer.height - 1;

    for (int i = 0; i < terminal.buffer.height; i++) {
      if (terminal.buffer.lines[i].getTrimmedLength() > 0) {
        firstNonEmpty = i;
        break;
      }
    }
    for (int i = terminal.buffer.height - 1; i >= firstNonEmpty; i--) {
      if (terminal.buffer.lines[i].getTrimmedLength() > 0) {
        lastNonEmpty = i;
        break;
      }
    }

    terminalController.setSelection(
      terminal.buffer.createAnchor(0, firstNonEmpty),
      terminal.buffer.createAnchor(terminal.viewWidth, lastNonEmpty),
      mode: SelectionMode.line,
    );
    _showQuickFeedback('Selected all terminal text');
  }

  void _showQuickFeedback(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
        width: 280,
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KEYBOARD EVENT INTERCEPTOR (CLASSIC SHORTCUTS + ALTGR FIX)
  // ─────────────────────────────────────────────────────────────────────────

  KeyEventResult _handleTerminalKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    final isPrimaryMod =
        (!kIsWeb && Platform.isMacOS) ? isMeta : (isCtrl && !isAlt);

    final key = event.logicalKey;

    // Handle TAB key for double-tab autocomplete
    if (key == LogicalKeyboardKey.tab && !isCtrl && !isAlt && !isMeta) {
      final doubleTabEnabled = ref.read(settingsProvider).enableDoubleTabAutocomplete;
      if (doubleTabEnabled && !terminal.isUsingAltBuffer && _isConnected) {
        final now = DateTime.now();
        final isDoubleTab = _lastTabPressTime != null &&
            now.difference(_lastTabPressTime!).inMilliseconds <= 450;
        _lastTabPressTime = now;

        if (isDoubleTab) {
          final handled = _triggerAutocomplete();
          if (handled) {
            return KeyEventResult.handled;
          }
        }
      }
    }

    // Dismiss suggestions on other keypresses
    if (_autocompleteSuggestions.isNotEmpty &&
        key != LogicalKeyboardKey.tab &&
        key != LogicalKeyboardKey.shiftLeft &&
        key != LogicalKeyboardKey.shiftRight &&
        key != LogicalKeyboardKey.controlLeft &&
        key != LogicalKeyboardKey.controlRight) {
      setState(() {
        _autocompleteSuggestions = [];
        _activeAutocompletePrefix = '';
      });
    }

    // 1. Fix AltGr (Ctrl + Alt on Windows/Linux) for Spanish/International keyboards
    // so characters like @, \, |, ~, [, ], {, }, # are inserted properly.
    if (isCtrl && isAlt && !isMeta) {
      final ch = event.character;
      if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 32) {
        terminal.textInput(ch);
        _scrollToBottom();
        return KeyEventResult.handled;
      }
    }

    // 2. Dedicated hardware Copy / Paste / Cut keys
    if (key == LogicalKeyboardKey.copy) {
      _copySelection(clearAfterCopy: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.paste) {
      _pasteClipboard();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.cut) {
      _cutSelection(cutLineIfNoSelection: true);
      return KeyEventResult.handled;
    }

    // 3. Classic Ctrl+Insert (Copy), Shift+Insert (Paste), Shift+Delete (Cut)
    if (key == LogicalKeyboardKey.insert) {
      if (isCtrl && !isShift && !isAlt) {
        _copySelection(clearAfterCopy: true);
        return KeyEventResult.handled;
      }
      if (isShift && !isCtrl && !isAlt) {
        _pasteClipboard();
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.delete && isShift && !isCtrl && !isAlt) {
      if (terminalController.selection != null) {
        _cutSelection();
        return KeyEventResult.handled;
      }
    }

    // 4. Primary modifier combinations (Ctrl on Windows/Linux/Android, Cmd on macOS)
    if (isPrimaryMod) {
      // COPY: Ctrl+C (when selection active) or Ctrl+Shift+C
      if (key == LogicalKeyboardKey.keyC) {
        if (isShift || terminalController.selection != null) {
          _copySelection(clearAfterCopy: true);
          return KeyEventResult.handled;
        }
        // No selection & no Shift -> send SIGINT (^C)
        terminal.keyInput(TerminalKey.keyC, ctrl: true);
        _scrollToBottom();
        return KeyEventResult.handled;
      }

      // PASTE: Ctrl+V or Ctrl+Shift+V
      if (key == LogicalKeyboardKey.keyV) {
        _pasteClipboard();
        return KeyEventResult.handled;
      }

      // CUT: Ctrl+X (when selection active) or Ctrl+Shift+X
      if (key == LogicalKeyboardKey.keyX) {
        if (isShift) {
          _cutSelection(cutLineIfNoSelection: true);
          return KeyEventResult.handled;
        }
        if (terminalController.selection != null) {
          _cutSelection();
          return KeyEventResult.handled;
        }
        // No selection -> let ^X (\x18) go to terminal (e.g. exit nano)
        terminal.keyInput(TerminalKey.keyX, ctrl: true);
        _scrollToBottom();
        return KeyEventResult.handled;
      }

      // SELECT ALL: Ctrl+Shift+A or Ctrl+A
      if (key == LogicalKeyboardKey.keyA) {
        if (isShift) {
          _selectAll();
          return KeyEventResult.handled;
        }
        // In main buffer, Ctrl+A selects all unless already selected (then sends ^A)
        if (!terminal.isUsingAltBuffer &&
            terminalController.selection == null) {
          _selectAll();
          return KeyEventResult.handled;
        } else {
          terminalController.clearSelection();
          terminal.keyInput(TerminalKey.keyA, ctrl: true);
          return KeyEventResult.handled;
        }
      }

      // ZOOM IN / OUT / RESET: Ctrl++, Ctrl+-, Ctrl+0
      if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd) {
        setState(() {
          _fontSize = (_fontSize + 1.0).clamp(8.0, 48.0);
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        setState(() {
          _fontSize = (_fontSize - 1.0).clamp(8.0, 48.0);
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit0 ||
          key == LogicalKeyboardKey.numpad0) {
        setState(() {
          _fontSize = ref.read(settingsProvider).defaultFontSize;
        });
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTOCOMPLETE IMPLEMENTATION (DOUBLE-TAB)
  // ─────────────────────────────────────────────────────────────────────────

  String _getActiveCommandText() {
    try {
      final (promptStartY, promptEndY) = _getActivePromptBounds();
      final curY = terminal.buffer.absoluteCursorY;
      final curX = terminal.buffer.cursorX;
      final firstLine = terminal.buffer.lines[promptStartY];
      final prefixEnd = _detectPromptPrefixEnd(
        firstLine,
        curY == promptStartY ? curX : firstLine.length,
      );

      final startCol = promptStartY == curY ? prefixEnd : 0;
      final endCol = curX;

      if (curY == promptStartY && endCol <= startCol) {
        return '';
      }

      final range = BufferRangeLine(
        CellOffset(startCol, promptStartY),
        CellOffset(endCol, curY),
      );
      return terminal.buffer.getText(range);
    } catch (_) {
      return '';
    }
  }

  bool _triggerAutocomplete() {
    final commandText = _getActiveCommandText();
    // Get last word or argument being typed
    final lastWordMatch = RegExp(r'[a-zA-Z0-9_\-\.\/]+$').firstMatch(commandText);
    final currentWord = lastWordMatch?.group(0) ?? commandText.trim();

    if (currentWord.isEmpty) {
      return false;
    }

    final matches = CommandDictionary.findMatches(currentWord);
    if (matches.isEmpty) {
      return false;
    }

    if (matches.length == 1) {
      // Single match: directly complete the remaining characters
      _applyAutocomplete(matches.first, currentWord);
      return true;
    } else {
      // Multiple matches: show autocomplete pill bar on top of the console
      setState(() {
        _autocompleteSuggestions = matches;
        _activeAutocompletePrefix = currentWord;
      });
      return true;
    }
  }

  void _applyAutocomplete(String suggestion, String typedPrefix) {
    String suffixToInsert = '';
    final suggestionLower = suggestion.toLowerCase();
    final typedLower = typedPrefix.toLowerCase();

    if (suggestionLower.startsWith(typedLower)) {
      // Exact prefix continuation: e.g. "letse" -> insert "ncrypt "
      suffixToInsert = '${suggestion.substring(typedPrefix.length)} ';
    } else {
      // Match was inside or different case: replace word or append
      // To replace cleanly: send backspaces for typed prefix then insert full suggestion
      final buffer = StringBuffer();
      for (int i = 0; i < typedPrefix.length; i++) {
        buffer.write('\x7f');
      }
      buffer.write('$suggestion ');
      _writeRawToShell(buffer.toString());
      setState(() {
        _autocompleteSuggestions = [];
        _activeAutocompletePrefix = '';
      });
      _scrollToBottom();
      return;
    }

    if (suffixToInsert.isNotEmpty) {
      _writeRawToShell(suffixToInsert);
    }
    setState(() {
      _autocompleteSuggestions = [];
      _activeAutocompletePrefix = '';
    });
    _scrollToBottom();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CURSOR & TOUCH NAVIGATION IN CONSOLE
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns `(promptStartY, promptEndY)` in absolute buffer coordinates for
  /// the current active command line (handling multi-line wrapped commands).
  (int, int) _getActivePromptBounds() {
    final int curY = terminal.buffer.absoluteCursorY
        .clamp(0, max(0, terminal.buffer.lines.length - 1))
        .toInt();
    int promptStartY = curY;
    while (promptStartY > 0 && terminal.buffer.lines[promptStartY].isWrapped) {
      promptStartY--;
    }
    int promptEndY = curY;
    while (promptEndY + 1 < terminal.buffer.lines.length &&
        terminal.buffer.lines[promptEndY + 1].isWrapped) {
      promptEndY++;
    }
    return (promptStartY, promptEndY);
  }

  /// Detects the column where the shell prompt prefix (e.g. `user@host:~$ `)
  /// ends on the first line of the prompt so clicking on the prompt prefix
  /// places the cursor at the beginning of the user's command.
  int _detectPromptPrefixEnd(BufferLine line, int maxSearchCol) {
    final int limit = min(maxSearchCol, line.length);
    if (limit <= 0) return 0;

    final text = line.getText(0, limit);
    const markers = ['\$ ', '# ', '% ', '> ', '❯ ', '➜ ', '» '];
    int bestEnd = 0;
    for (final marker in markers) {
      final idx = text.lastIndexOf(marker);
      if (idx != -1) {
        final endCol = idx + marker.length;
        if (endCol > bestEnd) {
          bestEnd = endCol;
        }
      }
    }
    return bestEnd.clamp(0, limit).toInt();
  }

  /// Moves the terminal cursor when the user clicks or taps on a cell.
  void _handleTerminalTapUp(TapUpDetails details, CellOffset cell) {
    if (_isMobile) {
      _terminalViewKey.currentState?.requestKeyboard();
    } else {
      _terminalFocusNode.requestFocus();
    }

    // If the user tapped simply to clear an existing selection, don't move cursor
    if (_hadSelectionOnPointerDown) {
      _hadSelectionOnPointerDown = false;
      return;
    }

    if (!_isConnected) return;

    // If the remote program handles mouse events natively (e.g. htop, mc, tmux),
    // xterm's TerminalGestureHandler already dispatches the mouse event.
    if (terminal.mouseMode != MouseMode.none) {
      return;
    }

    final leftSeq = terminal.cursorKeysMode ? '\x1bOD' : '\x1b[D';
    final rightSeq = terminal.cursorKeysMode ? '\x1bOC' : '\x1b[C';
    final upSeq = terminal.cursorKeysMode ? '\x1bOA' : '\x1b[A';
    final downSeq = terminal.cursorKeysMode ? '\x1bOB' : '\x1b[B';

    // CASE 1: Alternate Buffer (nano, vim, vi, less, etc. without mouse mode)
    if (terminal.isUsingAltBuffer) {
      final curX = terminal.buffer.cursorX;
      final curY = terminal.buffer.cursorY;
      final targetY = cell.y.clamp(0, terminal.viewHeight - 1);

      final targetLine = terminal.buffer.lines[targetY];
      final targetLineLen = targetLine.getTrimmedLength();
      final targetX = cell.x.clamp(0, targetLineLen);

      final deltaY = targetY - curY;
      final buffer = StringBuffer();

      if (deltaY == 0) {
        final deltaX = targetX - curX;
        if (deltaX < 0) {
          for (int i = 0; i < -deltaX; i++) {
            buffer.write(leftSeq);
          }
        } else if (deltaX > 0) {
          for (int i = 0; i < deltaX; i++) {
            buffer.write(rightSeq);
          }
        }
      } else {
        // Move to column 0 on current line first so intermediate short/empty
        // lines never skew the horizontal column calculation.
        for (int i = 0; i < curX; i++) {
          buffer.write(leftSeq);
        }
        final vSeq = deltaY < 0 ? upSeq : downSeq;
        for (int i = 0; i < deltaY.abs(); i++) {
          buffer.write(vSeq);
        }
        for (int i = 0; i < targetX; i++) {
          buffer.write(rightSeq);
        }
      }

      if (buffer.isNotEmpty) {
        _writeRawToShell(buffer.toString());
        if (_isMobile) HapticFeedback.selectionClick();
      }
      return;
    }

    // CASE 2: Main Buffer (bash, zsh, fish, sh, powershell, etc.)
    final (promptStartY, promptEndY) = _getActivePromptBounds();
    if (cell.y < promptStartY || cell.y > promptEndY) {
      return;
    }

    final curX = terminal.buffer.cursorX;
    final curY = terminal.buffer.absoluteCursorY;

    final firstLine = terminal.buffer.lines[promptStartY];
    final prefixEnd = _detectPromptPrefixEnd(
      firstLine,
      curY == promptStartY ? curX : firstLine.length,
    );

    int maxColOnTargetLine;
    if (cell.y == promptEndY) {
      maxColOnTargetLine = max(
        terminal.buffer.lines[promptEndY].getTrimmedLength(),
        curY == promptEndY ? curX : 0,
      );
    } else {
      maxColOnTargetLine = terminal.viewWidth - 1;
    }

    int targetX = cell.x.clamp(0, maxColOnTargetLine);
    if (cell.y == promptStartY) {
      targetX = max(targetX, prefixEnd);
    }

    final currentLinear = (curY - promptStartY) * terminal.viewWidth + curX;
    final targetLinear = (cell.y - promptStartY) * terminal.viewWidth + targetX;
    final delta = targetLinear - currentLinear;

    if (delta == 0) return;

    final buffer = StringBuffer();
    final seq = delta < 0 ? leftSeq : rightSeq;
    for (int i = 0; i < delta.abs(); i++) {
      buffer.write(seq);
    }

    _writeRawToShell(buffer.toString());
    if (_isMobile) HapticFeedback.selectionClick();
  }

  /// Handles 1-finger horizontal swipe on touchscreens to move the cursor
  /// smoothly left/right character by character.
  void _handlePointerDown(PointerDownEvent event) {
    _hadSelectionOnPointerDown = terminalController.selection != null;

    if (event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus) {
      if (_activeTouchPointer == null) {
        _activeTouchPointer = event.pointer;
        _touchStartPos = event.localPosition;
        _touchAccumX = 0.0;
        _isTouchHorizontalSwipe = false;
        _isTouchVerticalScroll = false;
      } else {
        // Multi-touch: cancel single-finger swipe tracking
        _activeTouchPointer = null;
        _isTouchHorizontalSwipe = false;
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _activeTouchPointer || _touchStartPos == null) return;
    if (terminalController.selection != null) return;

    final totalDelta = event.localPosition - _touchStartPos!;

    if (!_isTouchHorizontalSwipe && !_isTouchVerticalScroll) {
      if (totalDelta.distance < 10.0) return;
      if (totalDelta.dx.abs() > totalDelta.dy.abs() * 1.4) {
        _isTouchHorizontalSwipe = true;
      } else {
        _isTouchVerticalScroll = true;
      }
    }

    if (_isTouchHorizontalSwipe && _isConnected) {
      final cellWidth =
          _terminalViewKey.currentState?.renderTerminal.cellSize.width ?? 8.4;
      final stepWidth = max(cellWidth, 6.0);
      _touchAccumX += event.delta.dx;

      final steps = (_touchAccumX / stepWidth).truncate();
      if (steps != 0) {
        _touchAccumX -= steps * stepWidth;
        final seq = steps < 0
            ? (terminal.cursorKeysMode ? '\x1bOD' : '\x1b[D')
            : (terminal.cursorKeysMode ? '\x1bOC' : '\x1b[C');
        final buffer = StringBuffer();
        for (int i = 0; i < steps.abs(); i++) {
          buffer.write(seq);
        }
        _writeRawToShell(buffer.toString());
        HapticFeedback.selectionClick();
      }
    }
  }

  void _handlePointerUpOrCancel(PointerEvent event) {
    if (event.pointer == _activeTouchPointer) {
      _activeTouchPointer = null;
      _touchStartPos = null;
      _touchAccumX = 0.0;
      _isTouchHorizontalSwipe = false;
      _isTouchVerticalScroll = false;
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RIGHT-CLICK CONTEXT MENU
  // ─────────────────────────────────────────────────────────────────────────

  void _showTerminalContextMenu(TapDownDetails details, CellOffset cell) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final hasSel = terminalController.selection != null;
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      color: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.surfaceBorder),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          enabled: hasSel,
          child: _buildMenuRow(
            IconRegistry.copy,
            'Copy',
            'Ctrl+C',
            enabled: hasSel,
          ),
        ),
        PopupMenuItem<String>(
          value: 'cut',
          child: _buildMenuRow(
            IconRegistry.cut,
            hasSel ? 'Cut Selection' : 'Cut Line',
            'Ctrl+X',
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          child: _buildMenuRow(
            IconRegistry.paste,
            'Paste',
            'Ctrl+V',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'select_all',
          child: _buildMenuRow(
            IconRegistry.selectAll,
            'Select All',
            'Ctrl+A',
          ),
        ),
        PopupMenuItem<String>(
          value: 'move_here',
          child: _buildMenuRow(
            IconRegistry.cursorPadOff,
            'Move Cursor Here',
            'Click',
          ),
        ),
        PopupMenuItem<String>(
          value: 'clear',
          child: _buildMenuRow(
            IconRegistry.clear,
            'Clear Screen',
            'Ctrl+L',
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'copy':
        await _copySelection(clearAfterCopy: true);
        break;
      case 'cut':
        await _cutSelection(cutLineIfNoSelection: true);
        break;
      case 'paste':
        await _pasteClipboard();
        break;
      case 'select_all':
        _selectAll();
        break;
      case 'move_here':
        _hadSelectionOnPointerDown = false;
        _handleTerminalTapUp(
          TapUpDetails(
            kind: PointerDeviceKind.mouse,
            globalPosition: details.globalPosition,
            localPosition: details.localPosition,
          ),
          cell,
        );
        break;
      case 'clear':
        _writeRawToShell('\x0c');
        break;
    }
  }

  Widget _buildMenuRow(
    IconData icon,
    String label,
    String shortcut, {
    bool enabled = true,
  }) {
    final textColor =
        enabled ? AppColors.textPrimary : AppColors.textDisabled;
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.electricCyan : AppColors.textDisabled,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(color: textColor),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          shortcut,
          style: AppTextStyles.monoSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DIRECTIONAL & MACRO KEY DISPATCH (WITH MODIFIERS + AUTO-REPEAT)
  // ─────────────────────────────────────────────────────────────────────────

  void _sendSpecialKey(TerminalKey key) {
    final ctrl = _ctrlActive || HardwareKeyboard.instance.isControlPressed;
    final alt = _altActive || HardwareKeyboard.instance.isAltPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (ctrl || alt) {
      // Handle modifier + arrow/navigation sequences explicitly for full compatibility
      String? modSeq;
      final modCode = (ctrl && alt) ? '7' : (ctrl ? '5' : '3');
      switch (key) {
        case TerminalKey.arrowUp:
          modSeq = '\x1b[1;${modCode}A';
          break;
        case TerminalKey.arrowDown:
          modSeq = '\x1b[1;${modCode}B';
          break;
        case TerminalKey.arrowRight:
          modSeq = '\x1b[1;${modCode}C';
          break;
        case TerminalKey.arrowLeft:
          modSeq = '\x1b[1;${modCode}D';
          break;
        case TerminalKey.home:
          modSeq = '\x1b[1;${modCode}H';
          break;
        case TerminalKey.end:
          modSeq = '\x1b[1;${modCode}F';
          break;
        case TerminalKey.delete:
          modSeq = '\x1b[3;$modCode~';
          break;
        case TerminalKey.backspace:
          modSeq = ctrl ? '\x17' : '\x1b\x7f';
          break;
        default:
          break;
      }

      if (_ctrlActive || _altActive) {
        setState(() {
          _ctrlActive = false;
          _altActive = false;
        });
      }

      if (modSeq != null) {
        _writeRawToShell(modSeq);
        _scrollToBottom();
        return;
      }
    }

    terminal.keyInput(
      key,
      ctrl: ctrl,
      alt: alt,
      shift: shift,
    );
    _scrollToBottom();
  }

  void _startKeyRepeat(VoidCallback action) {
    _stopKeyRepeat();
    action();
    if (_isMobile) HapticFeedback.lightImpact();
    _keyRepeatTimer = Timer(const Duration(milliseconds: 350), () {
      _keyRepeatTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
        if (mounted) {
          action();
        } else {
          _stopKeyRepeat();
        }
      });
    });
  }

  void _stopKeyRepeat() {
    _keyRepeatTimer?.cancel();
    _keyRepeatTimer = null;
  }

  void _confirmDisconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('Disconnect Session'),
        content: Text(
            'Are you sure you want to disconnect from ${widget.profile.name}? Any running foreground processes will be killed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.softCrimson),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _sshEngine.disconnect(widget.profile.id);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI BUILDERS
  // ─────────────────────────────────────────────────────────────────────────

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
            icon: const Icon(IconRegistry.paste, color: AppColors.textSecondary, size: 20),
            onPressed: _pasteClipboard,
            tooltip: 'Paste (Ctrl+V)',
          ),
          IconButton(
            icon: Icon(
              _showCursorPad ? IconRegistry.cursorPadOn : IconRegistry.cursorPadOff,
              color: _showCursorPad ? AppColors.electricCyan : AppColors.textDisabled,
            ),
            onPressed: () {
              setState(() {
                _showCursorPad = !_showCursorPad;
              });
            },
            tooltip: 'Toggle Touch/Cursor Navigation Pad',
          ),
          IconButton(
            icon: Icon(
              _showSftp ? IconRegistry.sftpOn : IconRegistry.sftpOff,
              color: AppColors.electricCyan,
            ),
            onPressed: () {
              setState(() {
                _showSftp = !_showSftp;
              });
            },
            tooltip: 'Toggle SFTP Split View',
          ),
          IconButton(
            icon: Icon(
              _showMacroBar ? IconRegistry.macroBarOff : IconRegistry.macroBarOn,
              color: _showMacroBar ? AppColors.electricCyan : AppColors.textDisabled,
            ),
            onPressed: () {
              setState(() {
                _showMacroBar = !_showMacroBar;
              });
            },
            tooltip: 'Toggle Macro Bar',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out, color: AppColors.textDisabled),
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize - 1.0).clamp(8.0, 48.0);
              });
            },
            tooltip: 'Zoom Out (Ctrl+-)',
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: AppColors.textDisabled),
            onPressed: () {
              setState(() {
                _fontSize = (_fontSize + 1.0).clamp(8.0, 48.0);
              });
            },
            tooltip: 'Zoom In (Ctrl++)',
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new,
                color: AppColors.softCrimson),
            tooltip: 'Disconnect Session',
            onPressed: _confirmDisconnect,
          ),
        ],
      ),
      body: SafeArea(
        child: _showSftp
            ? ResizableSplit(
                isVertical: false,
                initialRatio: 0.6,
                child1: _buildTerminalContent(),
                child2: SftpScreen(
                  profile: widget.profile,
                  isEmbedded: true,
                ),
              )
            : _buildTerminalContent(),
      ),
    );
  }

  Widget _buildTerminalContent() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUpOrCancel,
                onPointerCancel: _handlePointerUpOrCancel,
                child: RawScrollbar(
                  controller: _scrollController,
                  thumbColor: AppColors.electricCyan.withValues(alpha: 0.35),
                  radius: const Radius.circular(4),
                  thickness: 6,
                  interactive: true,
                  child: TerminalView(
                    terminal,
                    key: _terminalViewKey,
                    controller: terminalController,
                    scrollController: _scrollController,
                    focusNode: _terminalFocusNode,
                    autofocus: true,
                    hardwareKeyboardOnly: _isDesktop,
                    deleteDetection: _isMobile,
                    simulateScroll: true,
                    keyboardType: TextInputType.text,
                    backgroundOpacity: 0.0,
                    onTapUp: _handleTerminalTapUp,
                    onSecondaryTapDown: _showTerminalContextMenu,
                    onKeyEvent: _handleTerminalKeyEvent,
                    textStyle: TerminalStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: _fontSize,
                    ),
                    theme: _buildTerminalTheme(),
                  ),
                ),
              ),
              if (_hasSelection)
                Positioned(
                  top: 12,
                  right: 16,
                  child: _buildFloatingSelectionBar(),
                ),
              if (_autocompleteSuggestions.isNotEmpty)
                Positioned(
                  bottom: 8,
                  left: 16,
                  right: 16,
                  child: _buildAutocompleteSuggestionsBar(),
                ),
              if (_showScrollToBottom)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: _buildScrollToBottomButton(),
                ),
              if (_showCursorPad) _buildCursorPadOverlay(),
            ],
          ),
        ),
        if (_showMacroBar) _buildMacroKeybar(),
      ],
    );
  }

  Widget _buildAutocompleteSuggestionsBar() {
    return Material(
      color: AppColors.surface1.withValues(alpha: 0.96),
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.electricCyan.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.auto_fix_high,
                  size: 15,
                  color: AppColors.electricCyan,
                ),
                const SizedBox(width: 6),
                Text(
                  'AUTOCOMPLETADO (DOBLE TAB)',
                  style: AppTextStyles.monoSmall.copyWith(
                    fontSize: 10,
                    color: AppColors.electricCyan,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    setState(() {
                      _autocompleteSuggestions = [];
                      _activeAutocompletePrefix = '';
                    });
                  },
                  child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _autocompleteSuggestions.map((suggestion) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: AppColors.surface2,
                      side: BorderSide(
                        color: AppColors.electricCyan.withValues(alpha: 0.4),
                      ),
                      label: Text(
                        suggestion,
                        style: AppTextStyles.monoSmall.copyWith(
                          color: AppColors.phosphorGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () {
                        _applyAutocomplete(suggestion, _activeAutocompletePrefix);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingSelectionBar() {
    return Material(
      color: AppColors.surface2.withValues(alpha: 0.95),
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.electricCyan.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSelectionActionChip(
              icon: IconRegistry.copy,
              label: 'Copy',
              onTap: () => _copySelection(clearAfterCopy: true),
            ),
            _buildSelectionActionChip(
              icon: IconRegistry.cut,
              label: 'Cut',
              onTap: () => _cutSelection(),
            ),
            _buildSelectionActionChip(
              icon: IconRegistry.paste,
              label: 'Paste',
              onTap: _pasteClipboard,
            ),
            _buildSelectionActionChip(
              icon: IconRegistry.selectAll,
              label: 'All',
              onTap: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              tooltip: 'Clear Selection',
              onPressed: () => terminalController.clearSelection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.electricCyan),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.monoSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollToBottomButton() {
    return Material(
      color: AppColors.surface2.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.electricCyan),
      ),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _scrollToBottom,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.keyboard_double_arrow_down,
                size: 16,
                color: AppColors.electricCyan,
              ),
              const SizedBox(width: 4),
              Text(
                'Bottom',
                style: AppTextStyles.monoSmall.copyWith(
                  color: AppColors.electricCyan,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating draggable D-Pad + 2D Trackpad for moving the cursor with mouse or touch.
  Widget _buildCursorPadOverlay() {
    return Positioned(
      left: _cursorPadOffset.dx,
      top: _cursorPadOffset.dy,
      child: Material(
        color: AppColors.surface1.withValues(alpha: 0.92),
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 196,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.electricCyan.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Draggable Header
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _cursorPadOffset = Offset(
                      (_cursorPadOffset.dx + details.delta.dx).clamp(0.0, 1200.0),
                      (_cursorPadOffset.dy + details.delta.dy).clamp(0.0, 800.0),
                    );
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.drag_indicator,
                        size: 15,
                        color: AppColors.electricCyan,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'CURSOR / TOUCH PAD',
                          style: AppTextStyles.monoSmall.copyWith(
                            fontSize: 10,
                            color: AppColors.electricCyan,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => _showCursorPad = false),
                        child: const Icon(
                          Icons.close,
                          size: 15,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Top row: HOME, UP, END
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPadButton('HOME', () => _sendSpecialKey(TerminalKey.home)),
                  _buildPadButton(
                    '↑',
                    () => _sendSpecialKey(TerminalKey.arrowUp),
                    repeatable: true,
                    primary: true,
                  ),
                  _buildPadButton('END', () => _sendSpecialKey(TerminalKey.end)),
                ],
              ),
              const SizedBox(height: 6),
              // Middle row: LEFT, 2D TRACKPAD, RIGHT
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPadButton(
                    '←',
                    () => _sendSpecialKey(TerminalKey.arrowLeft),
                    repeatable: true,
                    primary: true,
                  ),
                  GestureDetector(
                    onPanStart: (_) {
                      _trackpadAccumX = 0.0;
                      _trackpadAccumY = 0.0;
                    },
                    onPanUpdate: (details) {
                      _trackpadAccumX += details.delta.dx;
                      _trackpadAccumY += details.delta.dy;

                      const stepX = 10.0;
                      const stepY = 14.0;

                      final stepsX = (_trackpadAccumX / stepX).truncate();
                      if (stepsX != 0) {
                        _trackpadAccumX -= stepsX * stepX;
                        final seq = stepsX < 0
                            ? (terminal.cursorKeysMode ? '\x1bOD' : '\x1b[D')
                            : (terminal.cursorKeysMode ? '\x1bOC' : '\x1b[C');
                        _writeRawToShell(seq * stepsX.abs());
                        if (_isMobile) HapticFeedback.selectionClick();
                      }

                      final stepsY = (_trackpadAccumY / stepY).truncate();
                      if (stepsY != 0) {
                        _trackpadAccumY -= stepsY * stepY;
                        final seq = stepsY < 0
                            ? (terminal.cursorKeysMode ? '\x1bOA' : '\x1b[A')
                            : (terminal.cursorKeysMode ? '\x1bOB' : '\x1b[B');
                        _writeRawToShell(seq * stepsY.abs());
                        if (_isMobile) HapticFeedback.selectionClick();
                      }
                    },
                    onTap: () => _sendSpecialKey(TerminalKey.enter),
                    child: Container(
                      width: 68,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.electricCyan.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.touch_app,
                            size: 16,
                            color: AppColors.electricCyan,
                          ),
                          Text(
                            'SWIPE',
                            style: AppTextStyles.monoSmall.copyWith(
                              fontSize: 9,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildPadButton(
                    '→',
                    () => _sendSpecialKey(TerminalKey.arrowRight),
                    repeatable: true,
                    primary: true,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Bottom row: W← (Word Left), DOWN, W→ (Word Right)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildPadButton(
                    'W←',
                    () => _writeRawToShell('\x1b[1;5D'),
                    repeatable: true,
                  ),
                  _buildPadButton(
                    '↓',
                    () => _sendSpecialKey(TerminalKey.arrowDown),
                    repeatable: true,
                    primary: true,
                  ),
                  _buildPadButton(
                    'W→',
                    () => _writeRawToShell('\x1b[1;5C'),
                    repeatable: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPadButton(
    String label,
    VoidCallback onTrigger, {
    bool repeatable = false,
    bool primary = false,
  }) {
    return GestureDetector(
      onTapDown: repeatable ? (_) => _startKeyRepeat(onTrigger) : null,
      onTapUp: repeatable ? (_) => _stopKeyRepeat() : null,
      onTapCancel: repeatable ? _stopKeyRepeat : null,
      onTap: repeatable ? null : onTrigger,
      child: Container(
        width: 50,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary
              ? AppColors.electricCyan.withValues(alpha: 0.14)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: primary
                ? AppColors.electricCyan.withValues(alpha: 0.5)
                : AppColors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.monoSmall.copyWith(
            color: primary ? AppColors.electricCyan : AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: primary ? 15 : 11,
          ),
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
              color: _isConnected
                  ? AppColors.phosphorGreen
                  : AppColors.softCrimson,
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
      {'label': 'ESC', 'key': TerminalKey.escape},
      {'label': 'TAB', 'key': TerminalKey.tab},
      {'label': 'CTRL', 'isCtrl': true},
      {'label': 'ALT', 'isAlt': true},
      {'label': '←', 'key': TerminalKey.arrowLeft, 'repeatable': true},
      {'label': '↓', 'key': TerminalKey.arrowDown, 'repeatable': true},
      {'label': '↑', 'key': TerminalKey.arrowUp, 'repeatable': true},
      {'label': '→', 'key': TerminalKey.arrowRight, 'repeatable': true},
      {'label': 'COPY', 'action': 'copy'},
      {'label': 'CUT', 'action': 'cut'},
      {'label': 'PASTE', 'action': 'paste'},
      {'label': 'HOME', 'key': TerminalKey.home},
      {'label': 'END', 'key': TerminalKey.end},
      {'label': 'PG UP', 'key': TerminalKey.pageUp, 'repeatable': true},
      {'label': 'PG DN', 'key': TerminalKey.pageDown, 'repeatable': true},
      {'label': 'BKSP', 'key': TerminalKey.backspace, 'repeatable': true},
      {'label': 'DEL', 'key': TerminalKey.delete, 'repeatable': true},
      {'label': 'INS', 'key': TerminalKey.insert},
      {'label': 'F1', 'key': TerminalKey.f1},
      {'label': 'F2', 'key': TerminalKey.f2},
      {'label': 'F3', 'key': TerminalKey.f3},
      {'label': 'F4', 'key': TerminalKey.f4},
      {'label': 'F5', 'key': TerminalKey.f5},
      {'label': 'F6', 'key': TerminalKey.f6},
      {'label': 'F7', 'key': TerminalKey.f7},
      {'label': 'F8', 'key': TerminalKey.f8},
      {'label': 'F9', 'key': TerminalKey.f9},
      {'label': 'F10', 'key': TerminalKey.f10},
      {'label': 'F11', 'key': TerminalKey.f11},
      {'label': 'F12', 'key': TerminalKey.f12},
    ];

    return Container(
      color: AppColors.surface1,
      height: 48,
      child: ListView.builder(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final k = keys[index];
          final isCtrl = k['isCtrl'] == true;
          final isAlt = k['isAlt'] == true;
          final isRepeatable = k['repeatable'] == true;
          final action = k['action'] as String?;
          final termKey = k['key'] as TerminalKey?;

          bool isActive = false;
          String label = k['label'] as String;
          if (isCtrl) {
            isActive = _ctrlActive;
            if (isActive) label += ' ✓';
          } else if (isAlt) {
            isActive = _altActive;
            if (isActive) label += ' ✓';
          }

          void triggerKey() {
            if (isCtrl) {
              setState(() => _ctrlActive = !_ctrlActive);
            } else if (isAlt) {
              setState(() => _altActive = !_altActive);
            } else if (action != null) {
              switch (action) {
                case 'copy':
                  _copySelection(clearAfterCopy: true);
                  break;
                case 'cut':
                  _cutSelection(cutLineIfNoSelection: true);
                  break;
                case 'paste':
                  _pasteClipboard();
                  break;
              }
            } else if (termKey != null) {
              _sendSpecialKey(termKey);
            }
          }

          return GestureDetector(
            onTapDown: isRepeatable ? (_) => _startKeyRepeat(triggerKey) : null,
            onTapUp: isRepeatable ? (_) => _stopKeyRepeat() : null,
            onTapCancel: isRepeatable ? _stopKeyRepeat : null,
            child: InkWell(
              onTap: isRepeatable ? null : triggerKey,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.electricCyan.withValues(alpha: 0.2)
                      : Colors.transparent,
                  border: Border(
                    right:
                        const BorderSide(color: AppColors.surfaceBorder, width: 1),
                    bottom: isActive
                        ? const BorderSide(
                            color: AppColors.electricCyan, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isActive
                        ? AppColors.electricCyan
                        : (action != null
                            ? AppColors.phosphorGreen
                            : AppColors.textPrimary),
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    fontWeight: (isActive || action != null)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
