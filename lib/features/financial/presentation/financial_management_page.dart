import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/supabase_providers.dart';
import '../../boats/domain/boat.dart';
import '../../boats/providers.dart';
import '../../user_profiles/domain/profile_models.dart';
import '../../user_profiles/providers.dart';
import '../data/boat_financial_repository.dart';
import '../domain/boat_expense.dart';
import '../providers.dart';
import 'expense_form_page.dart';
import 'financial_reports_page.dart';

class FinancialManagementPage extends ConsumerWidget {
  const FinancialManagementPage({super.key});

  bool _hasOwnerProfile(List<UserProfileAssignment> profiles) {
    return profiles.any(
      (profile) =>
          profile.profileSlug == 'proprietario' ||
          profile.profileSlug == 'cotista',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(currentUserProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão financeira'),
        actions: [
          IconButton(
            tooltip: 'Relatórios de gastos',
            icon: const Icon(Icons.insights),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FinancialReportsPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: profilesAsync.when(
        data: (profiles) {
          if (!_hasOwnerProfile(profiles)) {
            return const _NoAccessState();
          }

          final user = ref.watch(userProvider);
          final boatsAsync = ref.watch(boatsProvider);

          return boatsAsync.when(
            data: (boats) {
              final manageableBoats =
                  boats.where((boat) => boat.canEdit(user?.id)).toList()
                    ..sort((a, b) => a.name.compareTo(b.name));

              if (manageableBoats.isEmpty) {
                return const _EmptyState(
                  title: 'Nenhuma embarcação habilitada',
                  message:
                      'Cadastre ou vincule-se como proprietário para registrar despesas.',
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(boatsProvider);
                  for (final boat in manageableBoats) {
                    ref.invalidate(boatExpensesProvider(boat.id));
                  }
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: manageableBoats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final boat = manageableBoats[index];
                    return _BoatExpensesCard(boat: boat);
                  },
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _ErrorView(
              message:
                  'Não foi possível carregar as embarcações: ${error.toString()}',
              onRetry: () {
                ref.invalidate(boatsProvider);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _ErrorView(
          message: 'Não foi possível carregar seus perfis.',
          onRetry: () => ref.invalidate(currentUserProfilesProvider),
        ),
      ),
    );
  }
}

class _BoatExpensesCard extends ConsumerWidget {
  const _BoatExpensesCard({required this.boat});

  final Boat boat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(boatExpensesProvider(boat.id));
    final currency = NumberFormat.simpleCurrency(
      locale: 'pt_BR',
      decimalDigits: 2,
    );

    Future<void> openForm([BoatExpense? expense]) async {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ExpenseFormPage(boat: boat, expense: expense),
        ),
      );
      if (!context.mounted) return;
      if (saved == true) {
        ref.invalidate(boatExpensesProvider(boat.id));
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              expense == null
                  ? 'Despesa cadastrada com sucesso.'
                  : 'Despesa atualizada com sucesso.',
            ),
          ),
        );
      }
    }

    Future<void> deleteExpense(BoatExpense expense) async {
      final messenger = ScaffoldMessenger.of(context);
      final repository = ref.read(boatFinancialRepositoryProvider);
      try {
        await repository.deleteExpense(expense);
        if (!context.mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Despesa removida.')),
        );
        ref.invalidate(boatExpensesProvider(boat.id));
      } catch (error) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Falha ao remover: $error')),
        );
      }
    }

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    boat.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova despesa'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Total: ${currency.format(_sumExpenses(expensesAsync.valueOrNull))}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            expensesAsync.when(
              data: (expenses) {
                if (expenses.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: _EmptyState(
                      title: 'Nenhuma despesa cadastrada',
                      message: 'Utilize o botão acima para registrar um gasto.',
                      dense: true,
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final expense in expenses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ExpenseTile(
                          expense: expense,
                          currency: currency,
                          onEdit: () => openForm(expense),
                          onDelete: () => deleteExpense(expense),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => _ErrorView(
                message: 'Falha ao carregar despesas do barco.',
                onRetry: () => ref.invalidate(boatExpensesProvider(boat.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _sumExpenses(List<BoatExpense>? expenses) {
    if (expenses == null || expenses.isEmpty) {
      return 0;
    }
    return expenses.fold<double>(
      0,
      (previousValue, element) => previousValue + element.amount,
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({
    required this.expense,
    required this.currency,
    this.onEdit,
    this.onDelete,
  });

  final BoatExpense expense;
  final NumberFormat currency;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final canEdit = expense.canEdit(user?.id);
    final theme = Theme.of(context);
    final dateLabel = DateFormat('dd/MM/yyyy').format(expense.incurredOn);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.category.label,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Registrado em $dateLabel por ${expense.createdByName ?? expense.createdByEmail ?? 'proprietário'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      currency.format(expense.amount),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (canEdit)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            onEdit?.call();
                          } else if (value == 'delete') {
                            onDelete?.call();
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Remover'),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
            if (expense.description != null &&
                expense.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                expense.description!.trim(),
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
            _DivisionStatus(expense: expense, currency: currency),
            if (expense.receiptPhotoUrl != null ||
                expense.receiptFileUrl != null) ...[
              const SizedBox(height: 12),
              _AttachmentRow(expense: expense),
            ],
          ],
        ),
      ),
    );
  }
}

class _DivisionStatus extends StatelessWidget {
  const _DivisionStatus({required this.expense, required this.currency});

  final BoatExpense expense;
  final NumberFormat currency;

  @override
  Widget build(BuildContext context) {
    if (!expense.hasDivision) {
      return Row(
        children: [
          Icon(Icons.person, color: Colors.grey.shade600, size: 18),
          const SizedBox(width: 8),
          Text(
            'Sem divisão registrada',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    final chipColor = expense.divisionCompleted
        ? Colors.green.shade100
        : Colors.orange.shade100;
    final chipLabel = expense.divisionCompleted
        ? 'Divisão concluída'
        : 'Divisão pendente';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(chipLabel), backgroundColor: chipColor),
            for (final share in expense.shares)
              Chip(
                avatar: const Icon(Icons.person, size: 16),
                label: Text(
                  '${share.ownerName}: ${currency.format(share.shareAmount)}',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.expense});

  final BoatExpense expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comprovantes',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (expense.receiptPhotoUrl != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.photo),
                label: const Text('Visualizar foto'),
                onPressed: () => _showImage(context, expense.receiptPhotoUrl!),
              ),
            if (expense.receiptFileUrl != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long),
                label: Text(expense.receiptFileName ?? 'Comprovante'),
                onPressed: () => _openLink(context, expense.receiptFileUrl!),
              ),
          ],
        ),
      ],
    );
  }

  static Future<void> _showImage(BuildContext context, String url) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  static Future<void> _openLink(BuildContext context, String url) async {
    final success = await launchUrlString(url);
    if (!success) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o comprovante.')),
      );
    }
  }
}

class _NoAccessState extends StatelessWidget {
  const _NoAccessState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Somente proprietários e coproprietários podem acessar a gestão financeira.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
    this.dense = false,
  });

  final String title;
  final String message;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: dense
          ? const EdgeInsets.symmetric(vertical: 8)
          : const EdgeInsets.symmetric(vertical: 64, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long,
            size: dense ? 32 : 64,
            color: Colors.blueGrey,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
