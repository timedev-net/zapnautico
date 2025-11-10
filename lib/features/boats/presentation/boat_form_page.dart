import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/supabase_providers.dart';
import '../../marinas/providers.dart';
import '../../user_profiles/providers.dart';
import '../data/boat_repository.dart';
import '../domain/boat.dart';
import '../domain/boat_enums.dart';
import '../domain/boat_photo.dart';
import '../domain/owner_summary.dart';
import '../providers.dart';

class BoatFormPage extends ConsumerStatefulWidget {
  const BoatFormPage({super.key, this.boat});

  final Boat? boat;

  bool get isEditing => boat != null;

  @override
  ConsumerState<BoatFormPage> createState() => _BoatFormPageState();
}

class _BoatFormPageState extends ConsumerState<BoatFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _registrationController = TextEditingController();
  final _fabricationYearController = TextEditingController();
  final _engineCountController = TextEditingController();
  final _engineBrandController = TextEditingController();
  final _engineModelController = TextEditingController();
  final _engineYearController = TextEditingController();
  final _enginePowerController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _trailerPlateController = TextEditingController();
  final _coOwnerEmailController = TextEditingController();

  late BoatType _boatType;
  late BoatPropulsionType _propulsionType;
  late BoatUsageType _usageType;
  late BoatSize _boatSize;
  String? _selectedMarinaId;
  final _coOwners = <OwnerSummary>[];
  String? _coOwnerError;

  final _retainedPhotos = <BoatPhoto>[];
  final _originalPhotos = <BoatPhoto>[];
  final _newPhotos = <XFile>[];

  bool _isSaving = false;
  bool _isCheckingCoOwner = false;

  @override
  void initState() {
    super.initState();
    _initializeFromBoat(widget.boat);
  }

  void _initializeFromBoat(Boat? boat) {
    if (boat == null) {
      _boatType = BoatType.lancha;
      _propulsionType = BoatPropulsionType.semPropulsao;
      _usageType = BoatUsageType.esporteRecreio;
      _boatSize = BoatSize.miuda;
      return;
    }

    _nameController.text = boat.name;
    _boatType = boat.boatType;
    if (boat.registrationNumber != null) {
      _registrationController.text = boat.registrationNumber!;
    }
    _fabricationYearController.text = boat.fabricationYear.toString();

    _propulsionType = boat.propulsionType;
    if (boat.engineCount != null) {
      _engineCountController.text = boat.engineCount.toString();
    }
    if (boat.engineBrand != null) {
      _engineBrandController.text = boat.engineBrand!;
    }
    if (boat.engineModel != null) {
      _engineModelController.text = boat.engineModel!;
    }
    if (boat.engineYear != null) {
      _engineYearController.text = boat.engineYear.toString();
    }
    if (boat.enginePower != null) {
      _enginePowerController.text = boat.enginePower!;
    }

    _usageType = boat.usageType;
    _boatSize = boat.size;

    if (boat.description != null) {
      _descriptionController.text = boat.description!;
    }
    if (boat.trailerPlate != null) {
      _trailerPlateController.text = boat.trailerPlate!;
    }

    _selectedMarinaId = boat.marinaId;
    for (final coOwner in boat.coOwners) {
      _coOwners.add(
        OwnerSummary(
          id: coOwner.userId,
          email: coOwner.email ?? '',
          fullName: coOwner.fullName ?? '',
        ),
      );
    }

    _originalPhotos.addAll(boat.photos);
    _retainedPhotos.addAll(boat.photos);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _registrationController.dispose();
    _fabricationYearController.dispose();
    _engineCountController.dispose();
    _engineBrandController.dispose();
    _engineModelController.dispose();
    _engineYearController.dispose();
    _enginePowerController.dispose();
    _descriptionController.dispose();
    _trailerPlateController.dispose();
    _coOwnerEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(currentUserProfilesProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return profilesAsync.when(
      data: (profiles) {
        final hasProprietarioAccess = profiles.any(
          (profile) => profile.profileSlug == 'proprietario',
        );

        if (!hasProprietarioAccess && !isAdmin) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                widget.isEditing ? 'Editar embarcação' : 'Nova embarcação',
              ),
            ),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Apenas usuários com perfil Proprietário podem cadastrar embarcações.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final marinasAsync = ref.watch(marinasProvider);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.isEditing ? 'Editar embarcação' : 'Nova embarcação',
            ),
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _buildPhotoPicker(context),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da embarcação',
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o nome da embarcação.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<BoatType>(
                    initialValue: _boatType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de embarcação',
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _boatType = value;
                      });
                    },
                    items: [
                      for (final type in BoatType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _registrationController,
                    decoration: const InputDecoration(
                      labelText: 'Número de inscrição',
                      hintText: 'Opcional',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fabricationYearController,
                    decoration: const InputDecoration(
                      labelText: 'Ano de fabricação',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o ano de fabricação.';
                      }
                      final parsed = int.tryParse(value);
                      final currentYear = DateTime.now().year + 1;
                      if (parsed == null ||
                          parsed < 1900 ||
                          parsed > currentYear) {
                        return 'Informe um ano válido.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<BoatPropulsionType>(
                    initialValue: _propulsionType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de propulsão',
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _propulsionType = value;
                        if (!_propulsionType.requiresEngineDetails) {
                          _engineCountController.clear();
                          _engineBrandController.clear();
                          _engineModelController.clear();
                          _engineYearController.clear();
                          _enginePowerController.clear();
                        }
                      });
                    },
                    items: [
                      for (final type in BoatPropulsionType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_propulsionType.requiresEngineDetails)
                    _buildEngineFields(),
                  DropdownButtonFormField<BoatUsageType>(
                    initialValue: _usageType,
                    decoration: const InputDecoration(labelText: 'Finalidade'),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _usageType = value;
                      });
                    },
                    items: [
                      for (final type in BoatUsageType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<BoatSize>(
                    initialValue: _boatSize,
                    decoration: const InputDecoration(
                      labelText: 'Porte da embarcação',
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _boatSize = value;
                      });
                    },
                    items: [
                      for (final size in BoatSize.values)
                        DropdownMenuItem(value: size, child: Text(size.label)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  marinasAsync.when(
                    data: (marinas) {
                      return DropdownButtonFormField<String?>(
                        initialValue: _selectedMarinaId,
                        decoration: const InputDecoration(
                          labelText: 'Marina vinculada',
                          hintText: 'Opcional',
                        ),
                        onChanged: (value) {
                          setState(() {
                            _selectedMarinaId = value;
                          });
                        },
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Nenhuma'),
                          ),
                          for (final marina in marinas)
                            DropdownMenuItem<String?>(
                              value: marina.id,
                              child: Text(marina.name),
                            ),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                    error: (error, stackTrace) => Text(
                      'Erro ao carregar marinas: $error',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _trailerPlateController,
                    decoration: const InputDecoration(
                      labelText: 'Placa da carretinha',
                      hintText: 'Opcional',
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Detalhes adicionais sobre a embarcação',
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 24),
                  _buildCoOwnersSection(context),
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
                    label: Text(
                      widget.isEditing
                          ? 'Salvar alterações'
                          : 'Cadastrar embarcação',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isEditing ? 'Editar embarcação' : 'Nova embarcação',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Erro ao carregar perfis: $error'),
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPicker(BuildContext context) {
    final totalPhotos = _retainedPhotos.length + _newPhotos.length;
    final remaining = 5 - totalPhotos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fotos da embarcação (até 5)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final photo in _retainedPhotos)
              _PhotoPreview(
                imageProvider: NetworkImage(photo.publicUrl),
                onRemove: () {
                  setState(() {
                    _retainedPhotos.removeWhere((p) => p.id == photo.id);
                  });
                },
              ),
            for (final file in _newPhotos)
              _PhotoPreview(
                imageProvider: kIsWeb
                    ? NetworkImage(file.path)
                    : FileImage(File(file.path)) as ImageProvider<Object>,
                onRemove: () {
                  setState(() {
                    _newPhotos.remove(file);
                  });
                },
              ),
            if (remaining > 0)
              _AddPhotoTile(
                remaining: remaining,
                onPickCamera: () => _pickPhoto(ImageSource.camera),
                onPickGallery: () => _pickPhoto(ImageSource.gallery),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildEngineFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _engineCountController,
          decoration: const InputDecoration(labelText: 'Quantidade de motores'),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (!_propulsionType.requiresEngineDetails) return null;
            final parsed = int.tryParse(value ?? '');
            if (parsed == null || parsed <= 0) {
              return 'Informe a quantidade de motores.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _engineBrandController,
          decoration: const InputDecoration(labelText: 'Marca do motor'),
          textCapitalization: TextCapitalization.words,
          validator: (value) {
            if (!_propulsionType.requiresEngineDetails) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Informe a marca do motor.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _engineModelController,
          decoration: const InputDecoration(labelText: 'Modelo do motor'),
          textCapitalization: TextCapitalization.words,
          validator: (value) {
            if (!_propulsionType.requiresEngineDetails) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Informe o modelo do motor.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _engineYearController,
          decoration: const InputDecoration(labelText: 'Ano do motor'),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (!_propulsionType.requiresEngineDetails) return null;
            final parsed = int.tryParse(value ?? '');
            final currentYear = DateTime.now().year + 1;
            if (parsed == null || parsed < 1900 || parsed > currentYear) {
              return 'Informe um ano válido.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _enginePowerController,
          decoration: const InputDecoration(
            labelText: 'Potência do motor',
            hintText: 'Ex: 150 HP',
          ),
          validator: (value) {
            if (!_propulsionType.requiresEngineDetails) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Informe a potência do motor.';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCoOwnersSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Coproprietários (opcional)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Informe o e-mail de um usuário com perfil Proprietário e toque em "Adicionar". É possível vincular vários coproprietários.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _coOwnerEmailController,
          decoration: InputDecoration(
            labelText: 'E-mail do coproprietário',
            suffixIcon: _isCheckingCoOwner
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: 'Limpar campo',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _coOwnerEmailController.clear();
                        _coOwnerError = null;
                      });
                    },
                  ),
            errorText: _coOwnerError,
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isCheckingCoOwner ? null : _addCoOwner,
              icon: const Icon(Icons.search),
              label: const Text('Validar e adicionar'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        if (_coOwners.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final owner in _coOwners)
                Chip(
                  label: Text(
                    owner.fullName.isNotEmpty
                        ? '${owner.fullName} (${owner.email})'
                        : (owner.email.isNotEmpty ? owner.email : owner.id),
                  ),
                  onDeleted: () {
                    setState(() {
                      _coOwners.removeWhere((item) => item.id == owner.id);
                    });
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final totalPhotos = _retainedPhotos.length + _newPhotos.length;
    if (totalPhotos >= 5) {
      _showMessage('É possível anexar no máximo 5 fotos.');
      return;
    }

    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      if (!mounted) return;

      setState(() {
        _newPhotos.add(file);
      });
    } catch (error) {
      _showMessage('Erro ao selecionar imagem: $error');
    }
  }

  Future<void> _addCoOwner() async {
    final email = _coOwnerEmailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _coOwnerError = null;
      });
      return;
    }

    final normalizedEmail = email.toLowerCase();

    setState(() {
      _isCheckingCoOwner = true;
      _coOwnerError = null;
    });

    try {
      final result = await ref
          .read(boatRepositoryProvider)
          .findOwnerByEmail(normalizedEmail);
      if (!mounted) return;

      if (result == null) {
        setState(() {
          _coOwnerError = 'Nenhum proprietário encontrado com este e-mail.';
        });
        return;
      }

      final primaryOwnerId =
          widget.boat?.primaryOwnerId ?? ref.read(userProvider)?.id;

      if (primaryOwnerId != null && result.id == primaryOwnerId) {
        setState(() {
          _coOwnerError =
              'O coproprietário deve ser diferente do proprietário principal.';
        });
        return;
      }

      final alreadyAdded = _coOwners.any((owner) => owner.id == result.id);
      if (alreadyAdded) {
        setState(() {
          _coOwnerError = 'Este coproprietário já está vinculado.';
        });
        return;
      }

      setState(() {
        _coOwners.add(result);
        _coOwnerError = null;
        _coOwnerEmailController.clear();
      });
      _showMessage('Coproprietário adicionado.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _coOwnerError = 'Erro ao validar coproprietário: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingCoOwner = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;
    if (_isSaving) return;

    final repository = ref.read(boatRepositoryProvider);

    final name = _nameController.text.trim();
    final registrationNumber = _registrationController.text.trim();
    final fabricationYear = int.parse(_fabricationYearController.text.trim());

    int? engineCount;
    int? engineYear;
    String? engineBrand;
    String? engineModel;
    String? enginePower;

    if (_propulsionType.requiresEngineDetails) {
      engineCount = int.tryParse(_engineCountController.text.trim());
      engineYear = int.tryParse(_engineYearController.text.trim());
      engineBrand = _engineBrandController.text.trim();
      engineModel = _engineModelController.text.trim();
      enginePower = _enginePowerController.text.trim();
    }

    final description = _descriptionController.text.trim();
    final trailerPlate = _trailerPlateController.text.trim();
    final marinaId = _selectedMarinaId;

    final coOwnerIds = _coOwners.map((owner) => owner.id).toList();

    setState(() {
      _isSaving = true;
    });

    try {
      if (widget.isEditing) {
        final boat = widget.boat!;
        final removedPhotos = _originalPhotos
            .where(
              (original) =>
                  !_retainedPhotos.any((photo) => photo.id == original.id),
            )
            .toList();

        await repository.updateBoat(
          boatId: boat.id,
          name: name,
          boatType: _boatType,
          registrationNumber: registrationNumber,
          fabricationYear: fabricationYear,
          propulsionType: _propulsionType,
          engineCount: engineCount,
          engineBrand: engineBrand,
          engineModel: engineModel,
          engineYear: engineYear,
          enginePower: enginePower,
          usageType: _usageType,
          boatSize: _boatSize,
          description: description.isEmpty ? null : description,
          trailerPlate: trailerPlate.isEmpty ? null : trailerPlate,
          marinaId: marinaId,
          coOwnerIds: coOwnerIds,
          retainedPhotos: List.of(_retainedPhotos),
          removedPhotos: removedPhotos,
          newPhotos: List.of(_newPhotos),
        );
        ref.invalidate(boatFutureProvider(boat.id));
      } else {
        await repository.createBoat(
          name: name,
          boatType: _boatType,
          registrationNumber: registrationNumber.isEmpty
              ? null
              : registrationNumber,
          fabricationYear: fabricationYear,
          propulsionType: _propulsionType,
          engineCount: engineCount,
          engineBrand: engineBrand,
          engineModel: engineModel,
          engineYear: engineYear,
          enginePower: enginePower,
          usageType: _usageType,
          boatSize: _boatSize,
          description: description.isEmpty ? null : description,
          trailerPlate: trailerPlate.isEmpty ? null : trailerPlate,
          marinaId: marinaId,
          coOwnerIds: coOwnerIds,
          newPhotos: List.of(_newPhotos),
        );
      }

      ref.invalidate(boatsProvider);

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

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.imageProvider, required this.onRemove});

  final ImageProvider imageProvider;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topRight,
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(
            image: imageProvider,
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 120,
              height: 120,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: IconButton(
            icon: const Icon(Icons.close),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({
    required this.remaining,
    required this.onPickCamera,
    required this.onPickGallery,
  });

  final int remaining;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.photo_camera_outlined),
            tooltip: 'Adicionar via câmera',
            onPressed: onPickCamera,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Adicionar da galeria',
            onPressed: onPickGallery,
          ),
          Text(
            '$remaining restante(s)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
