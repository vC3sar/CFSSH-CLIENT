import 'package:flutter/material.dart';

/// This file exists solely to prevent Flutter's Icon Tree Shaker from
/// removing glyphs that are selected at runtime (e.g., via ternary
/// expressions) rather than at compile-time.
///
/// Flutter's tree-shaker only preserves icon glyphs that appear as
/// `const IconData` references in the source. Any icon chosen dynamically
/// (e.g. `condition ? Icons.A : Icons.B`) can be stripped from the
/// Material Icons font in Release builds, making it invisible at runtime.
///
/// By listing every such icon here as a const field, we guarantee the
/// Tree Shaker will always keep those glyphs in the final binary.
///
/// DO NOT remove entries from this list without first verifying the icon
/// is no longer used dynamically anywhere in the app.
class IconRegistry {
  IconRegistry._(); // non-instantiable

  // ── Terminal screen (dynamic) ──────────────────────────────────────────────
  static const IconData sftpOn  = Icons.folder_shared;
  static const IconData sftpOff = Icons.folder_open;

  static const IconData macroBarOn  = Icons.keyboard;
  static const IconData macroBarOff = Icons.keyboard_hide;

  static const IconData cursorPadOn  = Icons.gamepad;
  static const IconData cursorPadOff = Icons.open_with;

  static const IconData copy      = Icons.content_copy;
  static const IconData cut       = Icons.content_cut;
  static const IconData paste     = Icons.content_paste;
  static const IconData selectAll = Icons.select_all;
  static const IconData clear     = Icons.clear_all;

  // ── QR Share & Import ─────────────────────────────────────────────────────
  static const IconData qrShare   = Icons.qr_code_2;
  static const IconData qrScan    = Icons.qr_code_scanner;
  static const IconData warning   = Icons.warning_amber_rounded;

  // ── SFTP layout toggle (dynamic) ──────────────────────────────────────────
  static const IconData layoutSideBySide = Icons.horizontal_distribute;
  static const IconData layoutStacked    = Icons.table_rows;

  // ── SFTP file list (dynamic per item type) ─────────────────────────────────
  static const IconData localFolder = Icons.folder;
  static const IconData localFile   = Icons.insert_drive_file;

  static const IconData remoteFolder = Icons.folder;
  static const IconData remoteFile   = Icons.cloud_circle;
}
