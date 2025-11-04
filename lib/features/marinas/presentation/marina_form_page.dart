import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../user_profiles/providers.dart';
import '../data/marina_repository.dart';
import '../domain/marina.dart';
import '../providers.dart';
import 'widgets/marina_location_picker.dart';

class MarinaFormPage extends ConsumerStatefulWidget {
  const MarinaFormPage({super.key, this.marina});

  final Marina? marina;

  @override
  ConsumerState<MarinaFormPage> createState() => _MarinaFormPageState();
}

class _MarinaFormPageState extends ConsumerState<MarinaFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _instagramController = TextEditingController();
  final _addressController = TextEditingController();
  LatLng? _location;
  XFile? _selectedImage;
  bool _isSaving = false;
  String? _existingPhotoUrl;
  String? _existingPhotoPath;

  bool get _isEditing => widget.marina != null;

  @override
  void initState() {
    super.initState();
    final marina = widget.marina;
    if (marina != null) {
      _nameController.text = marina.name;
      if (marina.whatsapp != null) {
        _whatsappController.text = marina.whatsapp!;
      }
      if (marina.instagram != null) {
        _instagramController.text = marina.instagram!;
      }
      if (marina.address != null) {
        _addressController.text = marina.address!;
      }
      _location = LatLng(marina.latitude, marina.longitude);
      _existingPhotoUrl = marina.photoUrl;
      _existingPhotoPath = marina.photoPath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _whatsappController.dispose();
    _instagramController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Marinas')),
        body: const Center(
          child: Text('Acesso restrito aos administradores.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar marina' : 'Nova marina'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildImagePicker(context),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome da marina',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o nome da marina.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _whatsappController,
                decoration: const InputDecoration(
                  labelText: 'Contato WhatsApp',
                  hintText: '(00) 98765-4321',
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _instagramController,
                decoration: const InputDecoration(
                  labelText: 'Perfil Instagram',
                  hintText: '@zapnautico',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Endereço',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              MarinaLocationPicker(
                initialLocation: _location,
                onChanged: (value) {
                  setState(() {
                    _location = value;
                  });
                },
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_isEditing ? 'Salvar alterações' : 'Cadastrar marina'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker(BuildContext context) {
    final theme = Theme.of(context);

    Widget preview;
    if (_selectedImage != null) {
      if (kIsWeb) {
        preview = Image.network(
          _selectedImage!.path,
          height: 180,
          fit: BoxFit.cover,
        );
      } else {
        preview = Image.file(
          File(_selectedImage!.path),
          height: 180,
          fit: BoxFit.cover,
        );
      }
    } else if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
      preview = Image.network(
        _existingPhotoUrl!,
        height: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
      );
    } else {
      preview = _buildPlaceholder(theme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: theme.colorScheme.surface,
            child: preview,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Câmera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeria'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Container(
      height: 180,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'Adicione uma foto da marina',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;
    if (_location == null) {
      _showMessage('Selecione a localização no mapa.');
      return;
    }
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    final repository = ref.read(marinaRepositoryProvider);

    final name = _nameController.text.trim();
    final whatsapp = _sanitizeWhatsapp(_whatsappController.text.trim());
    final instagram = _instagramController.text.trim().isEmpty
        ? null
        : _instagramController.text.trim();
    final address =
        _addressController.text.trim().isEmpty ? null : _addressController.text.trim();

    try {
      if (_isEditing) {
        final marina = widget.marina!;
        await repository.updateMarina(
          id: marina.id,
          name: name,
          whatsapp: whatsapp,
          instagram: instagram,
          address: address,
          latitude: _location!.latitude,
          longitude: _location!.longitude,
          photo: _selectedImage,
          currentPhotoPath: _existingPhotoPath,
          currentPhotoUrl: _existingPhotoUrl,
        );
      } else {
        await repository.createMarina(
          name: name,
          whatsapp: whatsapp,
          instagram: instagram,
          address: address,
          latitude: _location!.latitude,
          longitude: _location!.longitude,
          photo: _selectedImage,
        );
      }

      ref.invalidate(marinasProvider);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      _showMessage('Não foi possível salvar: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _sanitizeWhatsapp(String value) {
    if (value.isEmpty) return null;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
