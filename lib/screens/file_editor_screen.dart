import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class FileEditorScreen extends StatefulWidget {
  final File file;
  final String remotePath;
  final String filename;
  final Future<bool> Function(String localPath, String remotePath) onSave;

  const FileEditorScreen({
    super.key,
    required this.file,
    required this.remotePath,
    required this.filename,
    required this.onSave,
  });

  @override
  State<FileEditorScreen> createState() => _FileEditorScreenState();
}

class _FileEditorScreenState extends State<FileEditorScreen> {
  late TextEditingController _controller;
  bool _isSaving = false;
  bool _isModified = false;

  @override
  void initState() {
    super.initState();
    final content = widget.file.readAsStringSync();
    _controller = TextEditingController(text: content);
    _controller.addListener(() {
      if (!_isModified) {
        setState(() => _isModified = true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    // Preguntar sobreescribir
    final bool? overwrite = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface1,
        title: const Text('Guardar Archivo'),
        content: Text('¿Deseas sobreescribir el archivo "${widget.filename}" en el servidor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Omitir / Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.electricCyan, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sobreescribir'),
          ),
        ],
      ),
    );

    if (overwrite != true) return;

    setState(() => _isSaving = true);
    try {
      // Guardar local
      await widget.file.writeAsString(_controller.text);
      // Subir
      final success = await widget.onSave(widget.file.path, widget.remotePath);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Archivo guardado correctamente'), backgroundColor: AppColors.phosphorGreen),
        );
        setState(() => _isModified = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: AppColors.softCrimson),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvasBase,
      appBar: AppBar(
        title: Text(widget.filename),
        actions: [
          if (_isSaving)
            const Center(child: Padding(padding: EdgeInsets.only(right: 16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
          IconButton(
            icon: Icon(Icons.save, color: _isModified ? AppColors.electricCyan : AppColors.textSecondary),
            onPressed: _isSaving ? null : _handleSave,
            tooltip: 'Guardar',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _controller,
            maxLines: null,
            expands: true,
            style: AppTextStyles.monoMedium.copyWith(color: AppColors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Contenido del archivo...',
              hintStyle: TextStyle(color: AppColors.textDisabled),
            ),
          ),
        ),
      ),
    );
  }
}
