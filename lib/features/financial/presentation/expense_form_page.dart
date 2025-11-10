import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../boats/domain/boat.dart';
import '../data/boat_financial_repository.dart';
import '../domain/boat_expense.dart';
import '../domain/boat_expense_category.dart';
import '../domain/boat_expense_share.dart';

class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({required this.boat, this.expense, super.key});

  final Boat boat;
  final BoatExpense? expense;

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late BoatExpenseCategory _category;
  late DateTime _incurredOn;
  bool _divisionEnabled = false;
  bool _divisionCompleted = false;
  bool _isSubmitting = false;
  XFile? _selectedPhoto;
  PlatformFile? _selectedDocument;
  bool _removeExistingPhoto = false;
  bool _removeExistingDocument = false;
  late final List<_OwnerShareOption> _ownerOptions;
  final _currencyFormat = NumberFormat.simpleCurrency(locale: 'pt_BR');
  final _imagePicker = ImagePicker();

  bool get _hasMultipleOwners {
    if (widget.boat.coOwners.isNotEmpty) {
      return true;
    }
    final previousShares = widget.expense?.shares.length ?? 0;
    return previousShares > 1;
  }

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _category = expense?.category ?? BoatExpenseCategory.maintenance;
    _incurredOn = expense?.incurredOn ?? DateTime.now();
    _divisionEnabled =
        expense?.divisionConfigured ?? (widget.boat.coOwners.isNotEmpty);
    _divisionCompleted = expense?.divisionCompleted ?? false;
    _amountController = TextEditingController(
      text: expense != null
          ? expense.amount.toStringAsFixed(2).replaceAll('.', ',')
          : '',
    );
    _descriptionController = TextEditingController(
      text: expense?.description ?? '',
    );
    _ownerOptions = _buildOwnerOptions(expense);
    if (!_hasMultipleOwners) {
      _divisionEnabled = false;
      _divisionCompleted = false;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<_OwnerShareOption> _buildOwnerOptions(BoatExpense? expense) {
    final shares = expense?.shares ?? const <BoatExpenseShare>[];
    final shareMap = {for (final share in shares) share.ownerId: share};

    final options = <_OwnerShareOption>[];

    void addOwner({
      required String userId,
      required String? name,
      required String? email,
      bool isEditable = true,
    }) {
      if (userId.isEmpty || options.any((option) => option.userId == userId)) {
        return;
      }
      final share = shareMap[userId];
      options.add(
        _OwnerShareOption(
          userId: userId,
          displayName: (name != null && name.isNotEmpty)
              ? name
              : (email ?? 'Proprietário'),
          email: email,
          included: shareMap.isEmpty ? true : share != null,
          isEditable: isEditable,
        ),
      );
    }

    addOwner(
      userId: widget.boat.primaryOwnerId,
      name: widget.boat.primaryOwnerName,
      email: widget.boat.primaryOwnerEmail,
    );

    for (final coOwner in widget.boat.coOwners) {
      addOwner(
        userId: coOwner.userId,
        name: coOwner.fullName,
        email: coOwner.email,
      );
    }

    // Inclui participantes antigos que não estão mais vinculados ao barco
    for (final share in shares) {
      if (!options.any((option) => option.userId == share.ownerId)) {
        options.add(
          _OwnerShareOption(
            userId: share.ownerId,
            displayName: share.ownerName,
            email: share.ownerEmail,
            included: true,
            isEditable: false,
            detached: true,
          ),
        );
      }
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.expense != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar despesa' : 'Nova despesa'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.boat.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                _buildCategoryField(),
                const SizedBox(height: 16),
                _buildAmountField(),
                const SizedBox(height: 16),
                _buildDateField(context),
                const SizedBox(height: 16),
                _buildDescriptionField(),
                const SizedBox(height: 24),
                _buildDivisionSection(context),
                const SizedBox(height: 24),
                _buildPhotoSection(),
                const SizedBox(height: 16),
                _buildDocumentSection(),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : () => _handleSubmit(),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(isEditing ? 'Salvar alterações' : 'Cadastrar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryField() {
    return DropdownButtonFormField<BoatExpenseCategory>(
      decoration: const InputDecoration(
        labelText: 'Categoria',
        border: OutlineInputBorder(),
      ),
      initialValue: _category,
      items: [
        for (final category in BoatExpenseCategory.values)
          DropdownMenuItem(value: category, child: Text(category.label)),
      ],
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _category = value;
          });
        }
      },
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      decoration: const InputDecoration(
        labelText: 'Valor (R\$)',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.payments),
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: false,
      ),
      validator: (value) {
        final amount = _parseCurrency(value ?? '');
        if (amount == null || amount <= 0) {
          return 'Informe um valor válido.';
        }
        return null;
      },
    );
  }

  Widget _buildDateField(BuildContext context) {
    final dateLabel = DateFormat('dd/MM/yyyy').format(_incurredOn);
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Data do gasto',
        border: OutlineInputBorder(),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(dateLabel),
        trailing: IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _incurredOn,
              firstDate: DateTime(DateTime.now().year - 5),
              lastDate: DateTime(DateTime.now().year + 1),
            );
            if (picked != null) {
              setState(() {
                _incurredOn = picked;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      decoration: const InputDecoration(
        labelText: 'Descrição (opcional)',
        border: OutlineInputBorder(),
      ),
      maxLines: 3,
    );
  }

  Widget _buildDivisionSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          value: _divisionEnabled,
          onChanged: _hasMultipleOwners
              ? (value) {
                  setState(() {
                    _divisionEnabled = value;
                    if (!value) {
                      _divisionCompleted = false;
                    }
                  });
                }
              : null,
          title: const Text('Dividir custo entre proprietários'),
          subtitle: !_hasMultipleOwners
              ? const Text(
                  'Esta embarcação não possui coproprietários para divisão.',
                )
              : widget.boat.coOwners.isNotEmpty
              ? Text(
                  'Máximo de proprietários ativos: ${widget.boat.coOwners.length + 1}. Selecione quem participa desta despesa.',
                )
              : const Text(
                  'Divisão registrada anteriormente. Ajuste os participantes conforme necessário.',
                ),
        ),
        if (_divisionEnabled && _hasMultipleOwners) ...[
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final option in _ownerOptions)
                  CheckboxListTile(
                    value: option.included,
                    title: Text(option.displayName),
                    subtitle: option.detached
                        ? const Text(
                            'Proprietário não vinculado ao barco no momento.',
                          )
                        : null,
                    onChanged: option.isEditable
                        ? (value) {
                            setState(() {
                              option.included = value ?? false;
                            });
                          }
                        : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calculate, size: 18),
              const SizedBox(width: 8),
              Text(_divisionSummary()),
            ],
          ),
          SwitchListTile.adaptive(
            value: _divisionCompleted,
            onChanged: (value) {
              setState(() {
                _divisionCompleted = value;
              });
            },
            title: const Text('Divisão concluída'),
          ),
        ],
      ],
    );
  }

  String _divisionSummary() {
    if (_ownerOptions.isEmpty) {
      return 'Nenhum proprietário vinculado.';
    }
    final selected = _ownerOptions.where((option) => option.included).length;
    final amount = _parseCurrency(_amountController.text);
    if (selected == 0 || amount == null) {
      return 'Selecione ao menos um proprietário.';
    }
    final perOwner = _roundCurrency(amount / selected);
    return 'Valor por proprietário: ${_currencyFormat.format(perOwner)}';
  }

  Widget _buildPhotoSection() {
    final existingPhotoUrl = widget.expense?.receiptPhotoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Foto do gasto', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_selectedPhoto != null)
          _SelectedFileTile(
            label: 'Foto selecionada',
            fileName: _selectedPhoto!.name,
            onRemove: () {
              setState(() {
                _selectedPhoto = null;
              });
            },
          )
        else if (existingPhotoUrl != null && !_removeExistingPhoto)
          _ExistingAttachmentTile(
            label: 'Foto atual',
            onView: () => _previewImage(existingPhotoUrl),
            onRemove: () {
              setState(() {
                _removeExistingPhoto = true;
              });
            },
          ),
        TextButton.icon(
          onPressed: () async {
            final file = await _imagePicker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
            if (!mounted) return;
            if (file != null) {
              setState(() {
                _selectedPhoto = file;
                _removeExistingPhoto = true;
              });
            }
          },
          icon: const Icon(Icons.add_a_photo),
          label: Text(
            _selectedPhoto == null && existingPhotoUrl == null
                ? 'Adicionar foto'
                : 'Trocar foto',
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentSection() {
    final existingFileName = widget.expense?.receiptFileName;
    final existingFileUrl = widget.expense?.receiptFileUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comprovante em arquivo',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_selectedDocument != null)
          _SelectedFileTile(
            label: 'Arquivo selecionado',
            fileName: _selectedDocument!.name,
            onRemove: () {
              setState(() {
                _selectedDocument = null;
              });
            },
          )
        else if ((existingFileName != null || existingFileUrl != null) &&
            !_removeExistingDocument)
          _ExistingAttachmentTile(
            label: existingFileName ?? 'Comprovante atual',
            onView: existingFileUrl != null
                ? () => _openLink(existingFileUrl)
                : null,
            onRemove: () {
              setState(() {
                _removeExistingDocument = true;
              });
            },
          ),
        TextButton.icon(
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles(
              allowMultiple: false,
              withData: kIsWeb,
              type: FileType.custom,
              allowedExtensions: const [
                'pdf',
                'jpg',
                'jpeg',
                'png',
                'heic',
                'webp',
                'doc',
                'docx',
                'xls',
                'xlsx',
              ],
            );
            if (!mounted) return;
            if (result != null && result.files.isNotEmpty) {
              final file = result.files.first;
              if (file.size > 15 * 1024 * 1024) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Selecione arquivos de até 15MB.'),
                  ),
                );
                return;
              }
              setState(() {
                _selectedDocument = file;
                _removeExistingDocument = true;
              });
            }
          },
          icon: const Icon(Icons.attach_file),
          label: Text(
            _selectedDocument == null && existingFileName == null
                ? 'Adicionar comprovante'
                : 'Trocar comprovante',
          ),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final amount = _parseCurrency(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Informe um valor válido.')));
      return;
    }

    if (_divisionEnabled &&
        _ownerOptions.where((option) => option.included).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione ao menos um proprietário para divisão.'),
        ),
      );
      return;
    }

    final repository = ref.read(boatFinancialRepositoryProvider);
    final shares = _divisionEnabled
        ? _buildShares(amount)
        : const <BoatExpenseShare>[];

    setState(() {
      _isSubmitting = true;
    });

    try {
      if (widget.expense == null) {
        await repository.createExpense(
          boat: widget.boat,
          category: _category,
          amount: amount,
          incurredOn: _incurredOn,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          divisionEnabled: _divisionEnabled,
          divisionCompleted: _divisionCompleted,
          shares: shares,
          photo: _selectedPhoto,
          attachment: _selectedDocument,
        );
      } else {
        await repository.updateExpense(
          boat: widget.boat,
          expense: widget.expense!,
          category: _category,
          amount: amount,
          incurredOn: _incurredOn,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          divisionEnabled: _divisionEnabled,
          divisionCompleted: _divisionCompleted,
          shares: shares,
          newPhoto: _selectedPhoto,
          newAttachment: _selectedDocument,
          removePhoto: _removeExistingPhoto && _selectedPhoto == null,
          removeAttachment:
              _removeExistingDocument && _selectedDocument == null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  List<BoatExpenseShare> _buildShares(double amount) {
    final selectedOwners = _ownerOptions
        .where((option) => option.included)
        .toList();
    if (selectedOwners.isEmpty) {
      return const [];
    }
    final perOwnerAmount = _roundCurrency(amount / selectedOwners.length);
    return selectedOwners
        .map(
          (option) => BoatExpenseShare(
            ownerId: option.userId,
            ownerName: option.displayName,
            ownerEmail: option.email,
            shareAmount: perOwnerAmount,
          ),
        )
        .toList();
  }

  double _roundCurrency(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  double? _parseCurrency(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    if (cleaned.isEmpty) {
      return null;
    }
    return double.tryParse(cleaned);
  }

  Future<void> _previewImage(String url) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final success = await launchUrlString(url);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o arquivo.')),
      );
    }
  }
}

class _OwnerShareOption {
  _OwnerShareOption({
    required this.userId,
    required this.displayName,
    required this.email,
    this.included = true,
    this.isEditable = true,
    this.detached = false,
  });

  final String userId;
  final String displayName;
  final String? email;
  bool included;
  final bool isEditable;
  final bool detached;
}

class _SelectedFileTile extends StatelessWidget {
  const _SelectedFileTile({
    required this.label,
    required this.fileName,
    required this.onRemove,
  });

  final String label;
  final String fileName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(fileName),
      trailing: IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
    );
  }
}

class _ExistingAttachmentTile extends StatelessWidget {
  const _ExistingAttachmentTile({
    required this.label,
    this.onView,
    required this.onRemove,
  });

  final String label;
  final VoidCallback? onView;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Wrap(
        spacing: 8,
        children: [
          if (onView != null)
            IconButton(
              icon: const Icon(Icons.visibility),
              tooltip: 'Visualizar',
              onPressed: onView,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remover',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
