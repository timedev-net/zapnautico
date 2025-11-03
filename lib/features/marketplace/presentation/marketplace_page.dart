import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_providers.dart';
import '../data/listings_repository.dart';
import '../domain/listing.dart';

final listingsRepositoryProvider = Provider<ListingsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return ListingsRepository(client);
});

final listingsStreamProvider = StreamProvider<List<Listing>>((ref) {
  return ref.watch(listingsRepositoryProvider).watchListings();
});

class MarketplacePage extends ConsumerStatefulWidget {
  const MarketplacePage({super.key});

  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  @override
  Widget build(BuildContext context) {
    final listingsAsync = ref.watch(listingsStreamProvider);

    final content = listingsAsync.when(
      data: (listings) {
        if (listings.isEmpty) {
          return const _EmptyState(
            message: 'Nenhum anúncio cadastrado até o momento.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          itemBuilder: (context, index) {
            final listing = listings[index];
            return _ListingCard(listing: listing);
          },
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemCount: listings.length,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ErrorState(
        message: 'Falha ao carregar anúncios.',
        error: error,
        onRetry: () => ref.invalidate(listingsStreamProvider),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: content),
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Novo anúncio'),
            onPressed: () => _showCreateListingSheet(context),
          ),
        ),
      ],
    );
  }

  Future<void> _showCreateListingSheet(BuildContext context) async {
    final repository = ref.read(listingsRepositoryProvider);

    final titleController = TextEditingController();
    final priceController = TextEditingController();
    final descriptionController = TextEditingController();
    var type = 'venda';
    var currency = 'BRL';

    Future<void> submit() async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final title = titleController.text.trim();
      final description = descriptionController.text.trim();
      final price = double.tryParse(priceController.text.replaceAll(',', '.'));

      if (title.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Informe um título para o anúncio.')),
        );
        return;
      }
      try {
        await repository.publishListing(
          title: title,
          type: type,
          status: 'ativo',
          price: price,
          currency: price != null ? currency : null,
          description: description.isEmpty ? null : description,
        );
        if (!mounted) return;
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(content: Text('Anúncio publicado com sucesso.')),
        );
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Não foi possível publicar: $error')),
        );
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Novo anúncio',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Título',
                        hintText: 'Ex.: Lancha 32 pés para venda',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: const [
                        DropdownMenuItem(
                          value: 'venda',
                          child: Text('Venda'),
                        ),
                        DropdownMenuItem(
                          value: 'aluguel',
                          child: Text('Aluguel'),
                        ),
                        DropdownMenuItem(
                          value: 'acessorio',
                          child: Text('Acessório Náutico'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => type = value);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Tipo',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Preço',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: currency,
                      items: const [
                        DropdownMenuItem(
                          value: 'BRL',
                          child: Text('R\$ Real brasileiro'),
                        ),
                        DropdownMenuItem(
                          value: 'USD',
                          child: Text('US\$ Dólar'),
                        ),
                        DropdownMenuItem(
                          value: 'EUR',
                          child: Text('€ Euro'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => currency = value);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Moeda',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text('Publicar'),
                        onPressed: submit,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    titleController.dispose();
    priceController.dispose();
    descriptionController.dispose();
  }
}

class _ListingCard extends ConsumerWidget {
  const _ListingCard({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(listingsRepositoryProvider);
    final price =
        listing.price != null ? '${listing.currency ?? 'R\$'} ${listing.price!.toStringAsFixed(2)}' : 'Sob consulta';

    Future<void> toggleStatus() async {
      final newStatus = listing.status == 'ativo' ? 'inativo' : 'ativo';
      final messenger = ScaffoldMessenger.of(context);
      try {
        await repository.updateListingStatus(id: listing.id, status: newStatus);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Status atualizado para ${newStatus.toUpperCase()}.',
            ),
          ),
        );
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Falha ao atualizar o anúncio: $error')),
        );
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    listing.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(listing.type.toUpperCase()),
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              listing.description ?? 'Sem descrição detalhada.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  avatar: Icon(
                    listing.status == 'ativo'
                        ? Icons.check_circle
                        : Icons.pause_circle,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  label: Text('Status: ${listing.status}'),
                ),
                TextButton(
                  onPressed: toggleStatus,
                  child: Text(
                    listing.status == 'ativo'
                        ? 'Arquivar'
                        : 'Reativar',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_mall_directory, size: 80, color: Colors.blueGrey),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.error,
    required this.onRetry,
  });

  final String message;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error,
              size: 80,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Recarregar'),
            ),
          ],
        ),
      ),
    );
  }
}
