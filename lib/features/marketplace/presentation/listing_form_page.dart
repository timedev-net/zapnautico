import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/supabase_providers.dart';
import '../../boats/domain/boat.dart';
import '../../profile/data/user_contact_repository.dart';
import '../../profile/domain/user_contact_channel.dart';
import '../../profile/providers.dart';
import '../data/listings_repository.dart';
import '../domain/listing.dart';
import 'widgets/listing_location_picker.dart';

class ListingFormPage extends ConsumerStatefulWidget {
  const ListingFormPage({super.key, this.listing, this.boat});

  final Listing? listing;
  final Boat? boat;

  @override
  ConsumerState<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends ConsumerState<ListingFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _advertiserNameController = TextEditingController();
  final _instagramController = TextEditingController();
  final _cityController = TextEditingController();
  final _videoController = TextEditingController();
  final _imagePicker = ImagePicker();

  var _category = listingCategories.first;
  var _condition = ListingCondition.used;
  final Set<String> _selectedPayments = {'pix'};
  final List<_ListingMediaInput> _media = [];
  final List<ListingWhatsappContact> _contacts = [];
  String? _stateUf;
  bool _showEmail = false;
  bool _isSaving = false;
  double? _latitude;
  double? _longitude;
  bool _contactsSeededFromProfile = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromSources();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _advertiserNameController.dispose();
    _instagramController.dispose();
    _cityController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  void _hydrateFromSources() {
    final listing = widget.listing;
    if (listing != null) {
      _titleController.text = listing.title;
      if (listing.price != null) {
        _priceController.text = listing.price!
            .toStringAsFixed(2)
            .replaceAll('.', ',');
      }
      _descriptionController.text = listing.description ?? '';
      _advertiserNameController.text =
          listing.advertiserName ?? listing.ownerName ?? '';
      _instagramController.text = listing.instagramHandle ?? '';
      _cityController.text = listing.city ?? '';
      _stateUf = listing.state;
      _showEmail = listing.showEmail;
      _category = listing.category;
      _condition = listing.condition;
      _selectedPayments
        ..clear()
        ..addAll(
          listing.paymentOptions.isEmpty
              ? const ['pix']
              : listing.paymentOptions,
        );
      _latitude = listing.latitude;
      _longitude = listing.longitude;
      _videoController.text = listing.videoUrl ?? '';
      _media.addAll(listing.photos.map(_ListingMediaInput.fromPhoto));
      _contacts.addAll(listing.whatsappContacts);
    } else if (widget.boat != null) {
      final boat = widget.boat!;
      _titleController.text = boat.name;
      _descriptionController.text = boat.description ?? '';
      _advertiserNameController.text = boat.primaryOwnerName ?? '';
      _media.addAll(
        boat.photos
            .take(5)
            .map(
              (photo) => _ListingMediaInput.fromPhoto(
                ListingPhoto(
                  id: 'boat_${photo.id}',
                  publicUrl: photo.publicUrl,
                  position: photo.position,
                  bucket: 'boat_photos',
                  storagePath: photo.storagePath,
                  source: 'boat',
                ),
              ),
            ),
      );
    } else {
      final user = ref.read(userProvider);
      _advertiserNameController.text =
          user?.userMetadata?['full_name'] as String? ??
          user?.userMetadata?['name'] as String? ??
          user?.email ??
          '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(userContactsProvider);
    contactsAsync.whenData(_seedContactsFromProfile);

    final screenWidth = MediaQuery.of(context).size.width;
    final stackCategoryFields = screenWidth < 720;
    final stackLocationFields = screenWidth < 720;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listing == null ? 'Novo anúncio' : 'Editar anúncio'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Título'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o título do anúncio.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _advertiserNameController,
                decoration: const InputDecoration(
                  labelText: 'Nome do anunciante',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Informe o nome do anunciante.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _ResponsiveFieldsRow(
                stack: stackCategoryFields,
                firstChild: DropdownButtonFormField<String>(
                  initialValue: _category,
                  items: [
                    for (final category in listingCategories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  isExpanded: true,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _category = value);
                    }
                  },
                ),
                secondChild: DropdownButtonFormField<String>(
                  initialValue: _condition,
                  items: const [
                    DropdownMenuItem<String>(
                      value: ListingCondition.newItem,
                      child: Text('Novo'),
                    ),
                    DropdownMenuItem<String>(
                      value: ListingCondition.used,
                      child: Text('Usado'),
                    ),
                  ],
                  decoration: const InputDecoration(labelText: 'Condição'),
                  isExpanded: true,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _condition = value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Preço',
                  prefixText: 'R\$ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 16),
              Text(
                'Formas de pagamento aceitas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in marketplacePaymentOptions)
                    FilterChip(
                      label: Text(paymentOptionLabels[option] ?? option),
                      selected: _selectedPayments.contains(option),
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selectedPayments.add(option);
                          } else if (_selectedPayments.length > 1) {
                            _selectedPayments.remove(option);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _MediaPickerGrid(
                media: _media,
                onAddFromGallery: () => _pickPhoto(ImageSource.gallery),
                onAddFromCamera: () => _pickPhoto(ImageSource.camera),
                onRemove: (index) {
                  setState(() => _media.removeAt(index));
                },
                onMoveLeft: (index) => _moveMedia(index, -1),
                onMoveRight: (index) => _moveMedia(index, 1),
              ),
              const SizedBox(height: 24),
              Text(
                'Localização do anúncio',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _ResponsiveFieldsRow(
                stack: stackLocationFields,
                firstChild: TextFormField(
                  controller: _cityController,
                  decoration: const InputDecoration(labelText: 'Cidade'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe a cidade.';
                    }
                    return null;
                  },
                ),
                secondChild: DropdownButtonFormField<String>(
                  initialValue: _stateUf,
                  decoration: const InputDecoration(labelText: 'UF'),
                  isExpanded: true,
                  items: [
                    for (final uf in _brazilStates)
                      DropdownMenuItem(value: uf, child: Text(uf)),
                  ],
                  onChanged: (value) => setState(() => _stateUf = value),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Obrigatório';
                    }
                    return null;
                  },
                ),
                firstFlex: 2,
                gap: 12,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _selectLocationOnMap,
                icon: const Icon(Icons.map),
                label: Text(
                  _latitude != null && _longitude != null
                      ? 'Ponto definido (${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)})'
                      : 'Selecionar ponto no mapa',
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Contatos WhatsApp',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              _ContactList(
                contacts: _contacts,
                onRemove: (contact) {
                  setState(() => _contacts.remove(contact));
                },
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => _showAddContactSheet(contactsAsync),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar contato'),
              ),
              const SizedBox(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showEmail,
                onChanged: (value) => setState(() => _showEmail = value),
                title: const Text('Exibir meu e-mail no anúncio'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _instagramController,
                decoration: const InputDecoration(
                  labelText: 'Instagram',
                  prefixText: '@',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _videoController,
                decoration: const InputDecoration(
                  labelText: 'Link do vídeo (YouTube)',
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _submit,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    widget.listing == null
                        ? 'Salvar rascunho'
                        : 'Atualizar anúncio',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _seedContactsFromProfile(List<UserContactChannel> contacts) {
    if (_contactsSeededFromProfile ||
        _contacts.isNotEmpty ||
        contacts.isEmpty) {
      return;
    }

    UserContactChannel? selected;
    for (final contact in contacts) {
      if (contact.isWhatsapp) {
        selected = contact;
        break;
      }
    }
    final chosen = selected ?? contacts.first;

    _contactsSeededFromProfile = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _contacts.add(
          ListingWhatsappContact(
            name: chosen.label,
            number: chosen.normalizedWhatsapp,
            contactId: chosen.id,
          ),
        );
      });
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_media.length >= 5) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('É permitido até 5 fotos.')));
      return;
    }
    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1920,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _media.add(_ListingMediaInput.fromFile(file, bytes));
      });
    }
  }

  void _moveMedia(int index, int direction) {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= _media.length) return;
    setState(() {
      final item = _media.removeAt(index);
      _media.insert(newIndex, item);
    });
  }

  Future<void> _selectLocationOnMap() async {
    LatLng? initial;
    if (_latitude != null && _longitude != null) {
      initial = LatLng(_latitude!, _longitude!);
    } else {
      initial =
          await _geocodeCity() ??
          const LatLng(-22.9068, -43.1729); // Rio de Janeiro fallback
    }

    if (!mounted) return;
    final navigator = Navigator.of(context);
    final selected = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: ListingLocationPicker(
            initialLocation: initial,
            onChanged: (point) => navigator.pop(point),
          ),
        );
      },
    );

    if (selected != null) {
      setState(() {
        _latitude = selected.latitude;
        _longitude = selected.longitude;
      });
    }
  }

  Future<LatLng?> _geocodeCity() async {
    final city = _cityController.text.trim();
    final state = _stateUf;
    if (city.isEmpty || state == null) return null;

    final query = Uri.encodeComponent('$city, $state, Brasil');
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1',
    );
    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'ZapNauticoApp/1.0 (contato@zapnautico.com)',
      },
    );
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as List<dynamic>;
    if (data.isEmpty) return null;
    final item = data.first as Map<String, dynamic>;
    final lat = double.tryParse(item['lat'] as String? ?? '');
    final lon = double.tryParse(item['lon'] as String? ?? '');
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  Future<void> _showAddContactSheet(
    AsyncValue<List<UserContactChannel>> contactsAsync,
  ) async {
    final savedContacts =
        contactsAsync.asData?.value ?? const <UserContactChannel>[];

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final viewInsets = MediaQuery.of(sheetContext).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Adicionar contato',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  if (savedContacts.isEmpty)
                    const Text(
                      'Você ainda não cadastrou contatos preferenciais. '
                      'Crie um contato manualmente agora mesmo.',
                    )
                  else ...[
                    for (final contact in savedContacts)
                      ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(contact.label),
                        subtitle: Text(contact.normalizedWhatsapp),
                        trailing: const Icon(Icons.add),
                        onTap: () {
                          Navigator.of(sheetContext).pop(
                            ListingWhatsappContact(
                              name: contact.label,
                              number: contact.normalizedWhatsapp,
                              contactId: contact.id,
                            ),
                          );
                        },
                      ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop(_manualContactMarker);
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Contato manual'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    if (result is ListingWhatsappContact) {
      setState(() => _contacts.add(result));
      return;
    }

    if (result == _manualContactMarker) {
      final manual = await _showManualContactDialog();
      if (manual != null && mounted) {
        setState(() => _contacts.add(manual));
      }
    }
  }

  Future<ListingWhatsappContact?> _showManualContactDialog() {
    return showModalBottomSheet<ListingWhatsappContact>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ManualContactSheet(),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione pelo menos um contato do WhatsApp.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);

    final retainedPhotos = <ListingPhoto>[];
    final newFiles = <XFile>[];
    for (var index = 0; index < _media.length; index++) {
      final entry = _media[index];
      if (entry.photo != null) {
        retainedPhotos.add(entry.photo!.copyWith(position: index));
      } else if (entry.file != null) {
        newFiles.add(entry.file!);
      }
    }

    final priceText = _priceController.text
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();
    final price = priceText.isNotEmpty ? double.tryParse(priceText) : null;

    try {
      final repo = ref.read(listingsRepositoryProvider);
      if (widget.listing == null) {
        await repo.createListing(
          title: _titleController.text.trim(),
          category: _category,
          condition: _condition,
          paymentOptions: _selectedPayments.toList(),
          whatsappContacts: _contacts,
          retainedPhotos: retainedPhotos,
          newPhotos: newFiles,
          advertiserName: _advertiserNameController.text.trim(),
          price: price,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          city: _cityController.text.trim(),
          state: _stateUf,
          latitude: _latitude,
          longitude: _longitude,
          instagramHandle: _sanitizeInstagram(_instagramController.text),
          showEmail: _showEmail,
          videoUrl: _videoController.text.trim().isEmpty
              ? null
              : _videoController.text.trim(),
          boatId: widget.boat?.id,
        );
      } else {
        await repo.updateListing(
          listing: widget.listing!,
          title: _titleController.text.trim(),
          category: _category,
          condition: _condition,
          paymentOptions: _selectedPayments.toList(),
          whatsappContacts: _contacts,
          retainedPhotos: retainedPhotos,
          newPhotos: newFiles,
          advertiserName: _advertiserNameController.text.trim(),
          price: price,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          city: _cityController.text.trim(),
          state: _stateUf,
          latitude: _latitude,
          longitude: _longitude,
          instagramHandle: _sanitizeInstagram(_instagramController.text),
          showEmail: _showEmail,
          videoUrl: _videoController.text.trim().isEmpty
              ? null
              : _videoController.text.trim(),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.listing == null
                ? 'Anúncio salvo. Aguarda publicação.'
                : 'Anúncio atualizado.',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Falha ao salvar: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  String? _sanitizeInstagram(String text) {
    final trimmed = text.trim().replaceAll('@', '');
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class _MediaPickerGrid extends StatelessWidget {
  const _MediaPickerGrid({
    required this.media,
    required this.onAddFromGallery,
    required this.onAddFromCamera,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
  });

  final List<_ListingMediaInput> media;
  final VoidCallback onAddFromGallery;
  final VoidCallback onAddFromCamera;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onMoveLeft;
  final ValueChanged<int> onMoveRight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mídia (até 5 fotos)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < media.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _MediaPreview(media: media[i]),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: Colors.white,
                            onPressed: () => onRemove(i),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                          ),
                          onPressed: () => onMoveLeft(i),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                          ),
                          onPressed: () => onMoveRight(i),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            if (media.length < 5)
              GestureDetector(
                onTap: onAddFromGallery,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.photo_library_outlined),
                  ),
                ),
              ),
            if (media.length < 5)
              GestureDetector(
                onTap: onAddFromCamera,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  child: const Center(child: Icon(Icons.photo_camera_outlined)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.media});

  final _ListingMediaInput media;

  @override
  Widget build(BuildContext context) {
    if (media.photo != null) {
      return Image.network(
        media.photo!.publicUrl,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 120,
          height: 120,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image),
        ),
      );
    }
    if (media.bytes != null) {
      return Image.memory(
        media.bytes!,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      );
    }
    return Container(
      width: 120,
      height: 120,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

class _ContactList extends StatelessWidget {
  const _ContactList({required this.contacts, required this.onRemove});

  final List<ListingWhatsappContact> contacts;
  final ValueChanged<ListingWhatsappContact> onRemove;

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: const Text('Nenhum contato adicionado ainda.'),
      );
    }

    return Column(
      children: [
        for (final contact in contacts)
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(contact.name),
              subtitle: Text(contact.formattedNumber),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onRemove(contact),
              ),
            ),
          ),
      ],
    );
  }
}

class _ManualContactSheet extends ConsumerStatefulWidget {
  const _ManualContactSheet();

  @override
  ConsumerState<_ManualContactSheet> createState() =>
      _ManualContactSheetState();
}

class _ManualContactSheetState extends ConsumerState<_ManualContactSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dddController;
  late final TextEditingController _numberController;
  bool _saveForLater = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _dddController = TextEditingController();
    _numberController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dddController.dispose();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final contact = ListingWhatsappContact(
      name: _nameController.text.trim(),
      number:
          '+55${_dddController.text.trim()}${_numberController.text.trim()}',
    );

    try {
      if (_saveForLater) {
        await ref
            .read(userContactRepositoryProvider)
            .upsertContact(
              channel: 'whatsapp',
              label: contact.name,
              value: contact.number,
            );
        ref.invalidate(userContactsProvider);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorText = '$error');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(contact);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Novo contato',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Informe o nome.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _dddController,
                        decoration: const InputDecoration(labelText: 'DDD'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        validator: (value) {
                          if (value == null || value.length != 2) {
                            return 'DDD inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _numberController,
                        decoration: const InputDecoration(
                          labelText: 'Número',
                          hintText: '987654321',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                        validator: (value) {
                          if (value == null || value.length < 8) {
                            return 'Número inválido';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _saveForLater,
                  onChanged: (value) => setState(() => _saveForLater = value),
                  title: const Text('Salvar em meus contatos'),
                ),
                if (_errorText != null) ...[
                  Text(
                    _errorText!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save),
                    label: const Text('Adicionar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListingMediaInput {
  _ListingMediaInput._({this.photo, this.file, this.bytes});

  factory _ListingMediaInput.fromPhoto(ListingPhoto photo) {
    return _ListingMediaInput._(photo: photo);
  }

  factory _ListingMediaInput.fromFile(XFile file, Uint8List bytes) {
    return _ListingMediaInput._(file: file, bytes: bytes);
  }

  final ListingPhoto? photo;
  final XFile? file;
  final Uint8List? bytes;
}

const _manualContactMarker = '_manual_contact_selection';

class _ResponsiveFieldsRow extends StatelessWidget {
  const _ResponsiveFieldsRow({
    required this.stack,
    required this.firstChild,
    required this.secondChild,
    this.firstFlex = 1,
    this.gap = 16,
  });

  final bool stack;
  final Widget firstChild;
  final Widget secondChild;
  final int firstFlex;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [firstChild, const SizedBox(height: 12), secondChild],
      );
    }

    return Row(
      children: [
        Expanded(flex: firstFlex, child: firstChild),
        SizedBox(width: gap),
        Expanded(child: secondChild),
      ],
    );
  }
}

const _brazilStates = <String>[
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];
