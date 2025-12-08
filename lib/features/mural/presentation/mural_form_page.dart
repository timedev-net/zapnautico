import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../data/marina_wall_repository.dart';
import '../domain/marina_wall_post.dart';

class MuralFormPage extends ConsumerStatefulWidget {
  const MuralFormPage({super.key, required this.marinaId, this.marinaName});

  final String marinaId;
  final String? marinaName;

  @override
  ConsumerState<MuralFormPage> createState() => _MuralFormPageState();
}

class _MuralFormPageState extends ConsumerState<MuralFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _dateFormat = DateFormat('dd/MM/yyyy');

  var _type = muralPostTypes.first;
  late DateTime _startDate;
  late DateTime _endDate;
  XFile? _selectedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _startDate = DateTime(today.year, today.month, today.day);
    _endDate = _startDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final marinaLabel = widget.marinaName?.isNotEmpty == true
        ? widget.marinaName!
        : 'sua marina';

    return Scaffold(
      appBar: AppBar(title: const Text('Nova publicacao')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Publicando como $marinaLabel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Titulo'),
                maxLength: 120,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o titulo.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Tipo'),
                isExpanded: true,
                initialValue: _type,
                items: [
                  for (final option in muralPostTypes)
                    DropdownMenuItem(
                      value: option,
                      child: Text(muralPostTypeLabels[option] ?? option),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _type = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descricao',
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 6,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Descreva o anuncio do mural.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Periodo da publicacao',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _pickDate(isStart: true),
                      icon: const Icon(Icons.event),
                      label: Text('Inicio: ${_dateFormat.format(_startDate)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving
                          ? null
                          : () => _pickDate(isStart: false),
                      icon: const Icon(Icons.event_available),
                      label: Text('Fim: ${_dateFormat.format(_endDate)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Imagem (opcional)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_selectedImage != null)
                Card(
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_selectedImage!.path),
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainer,
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _isSaving
                                ? null
                                : () => setState(() => _selectedImage = null),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: const Center(
                    child: Text('Nenhuma imagem selecionada'),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galeria'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Camera'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSaving ? 'Salvando...' : 'Publicar no mural'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final firstDate = DateTime(DateTime.now().year - 1);
    final lastDate = DateTime(DateTime.now().year + 2);
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: isStart ? 'Data de inicio' : 'Data final',
    );

    if (selected != null) {
      setState(() {
        if (isStart) {
          _startDate = selected;
          if (_endDate.isBefore(selected)) {
            _endDate = selected;
          }
        } else {
          _endDate = selected;
        }
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1920,
    );
    if (picked != null) {
      setState(() => _selectedImage = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await ref
          .read(marinaWallRepositoryProvider)
          .createPost(
            marinaId: widget.marinaId,
            title: _titleController.text,
            description: _descriptionController.text,
            type: _type,
            startDate: _startDate,
            endDate: _endDate,
            image: _selectedImage,
          );

      if (!mounted) return;
      Navigator.of(context).pop(result.post);

      var message = 'Publicacao criada no mural.';
      if (result.pushFailed) {
        message = '$message Push nao enviado: ${result.pushError}.';
      } else if (result.pushResult != null &&
          result.pushResult!['delivered'] != null) {
        final delivered = result.pushResult!['delivered'];
        message = '$message Push enviado para $delivered dispositivo(s).';
      }

      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Falha ao salvar publicacao: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
