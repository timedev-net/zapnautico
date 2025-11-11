import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/supabase_providers.dart';
import '../../user_profiles/providers.dart';
import '../data/listings_repository.dart';
import '../domain/listing.dart';
import 'listing_actions.dart';
import 'listing_detail_page.dart';
import 'listing_form_page.dart';

final listingsStreamProvider = StreamProvider<List<Listing>>((ref) {
  return ref.watch(listingsRepositoryProvider).watchListings();
});

final marketplaceSearchProvider = StateProvider<String>((ref) => '');
final marketplaceCategoryFilterProvider =
    StateProvider<Set<String>>((ref) => <String>{});
final marketplaceSortProvider = StateProvider<MarketplaceSortOption>(
  (ref) => MarketplaceSortOption.dateDesc,
);
final marketplaceShowMineProvider = StateProvider<bool>((ref) => false);

enum MarketplaceSortOption { priceAsc, priceDesc, dateDesc, titleAsc }

class MarketplacePage extends ConsumerStatefulWidget {
  const MarketplacePage({super.key});

  @override
  ConsumerState<MarketplacePage> createState() => _MarketplacePageState();
}

class _MarketplacePageState extends ConsumerState<MarketplacePage> {
  final _searchController = TextEditingController();
  final _currencyFormat =
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      ref.read(marketplaceSearchProvider.notifier).state =
          _searchController.text.trim();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listingsAsync = ref.watch(listingsStreamProvider);
    final searchText = ref.watch(marketplaceSearchProvider);
    final categoryFilter = ref.watch(marketplaceCategoryFilterProvider);
    final sortOption = ref.watch(marketplaceSortProvider);
    final showOnlyMine = ref.watch(marketplaceShowMineProvider);
    final user = ref.watch(userProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final canShowMineToggle = user != null;

    return Stack(
      children: [
        Column(
          children: [
            _MarketplaceFiltersBar(
              searchController: _searchController,
              canShowMineToggle: canShowMineToggle && !isAdmin,
            ),
            Expanded(
              child: listingsAsync.when(
                data: (listings) {
                  final filtered = _filterListings(
                    listings: listings,
                    searchText: searchText,
                    categories: categoryFilter,
                    sortOption: sortOption,
                    showOnlyMine: showOnlyMine && !isAdmin,
                    userId: user?.id,
                    isAdmin: isAdmin,
                  );
                  if (filtered.isEmpty) {
                    return const _EmptyState(
                      message: 'Nenhum anúncio encontrado com os filtros atuais.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(listingsStreamProvider);
                      await ref.read(listingsStreamProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final listing = filtered[index];
                        final isOwner = listing.ownerId == user?.id;
                        return _ListingCard(
                          listing: listing,
                          isOwner: isOwner,
                          isAdmin: isAdmin,
                          currencyFormat: _currencyFormat,
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stackTrace) => _ErrorState(
                  message: 'Falha ao carregar anúncios.',
                  error: error,
                  onRetry: () => ref.invalidate(listingsStreamProvider),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: const Text('Novo anúncio'),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await navigator.push(
                MaterialPageRoute<void>(
                  builder: (_) => const ListingFormPage(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Listing> _filterListings({
    required List<Listing> listings,
    required String searchText,
    required Set<String> categories,
    required MarketplaceSortOption sortOption,
    required bool showOnlyMine,
    required String? userId,
    required bool isAdmin,
  }) {
    final normalizedSearch = searchText.toLowerCase();
    final filtered = listings.where((listing) {
      final isOwner = listing.ownerId == userId;
      if (!isAdmin) {
        if (showOnlyMine) {
          if (!isOwner) return false;
        } else if (!isOwner && listing.status != ListingStatus.published) {
          return false;
        }
      }

      if (categories.isNotEmpty && !categories.contains(listing.category)) {
        return false;
      }

      if (normalizedSearch.isNotEmpty) {
        final haystack = [
          listing.title,
          listing.description ?? '',
          listing.city ?? '',
          listing.state ?? '',
          listing.advertiserName ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(normalizedSearch)) {
          return false;
        }
      }
      return true;
    }).toList();

    filtered.sort((a, b) {
      switch (sortOption) {
        case MarketplaceSortOption.priceAsc:
          final priceA = a.price ?? double.maxFinite;
          final priceB = b.price ?? double.maxFinite;
          final result = priceA.compareTo(priceB);
          if (result != 0) return result;
          return b.createdAt.compareTo(a.createdAt);
        case MarketplaceSortOption.priceDesc:
          final priceA = a.price ?? -1;
          final priceB = b.price ?? -1;
          final result = priceB.compareTo(priceA);
          if (result != 0) return result;
          return b.createdAt.compareTo(a.createdAt);
        case MarketplaceSortOption.titleAsc:
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case MarketplaceSortOption.dateDesc:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    return filtered;
  }
}

class _MarketplaceFiltersBar extends ConsumerWidget {
  const _MarketplaceFiltersBar({
    required this.searchController,
    required this.canShowMineToggle,
  });

  final TextEditingController searchController;
  final bool canShowMineToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategories = ref.watch(marketplaceCategoryFilterProvider);
    final sortOption = ref.watch(marketplaceSortProvider);
    final showMine = ref.watch(marketplaceShowMineProvider);

    final hasActiveFilters = selectedCategories.isNotEmpty ||
        showMine ||
        sortOption != MarketplaceSortOption.dateDesc;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: searchController,
              builder: (context, value, _) {
                return TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: 'Buscar anúncios',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (value.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              ref
                                  .read(marketplaceSearchProvider.notifier)
                                  .state = '';
                            },
                          ),
                        IconButton(
                          tooltip: 'Opções avançadas',
                          icon: const Icon(Icons.tune),
                          onPressed: () => _openAdvancedFilters(
                            context,
                            ref,
                            canShowMineToggle: canShowMineToggle,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final category in selectedCategories.take(3))
                    Chip(
                      label: Text(category),
                      onDeleted: () {
                        final notifier = ref.read(
                          marketplaceCategoryFilterProvider.notifier,
                        );
                        notifier.state = {
                          for (final current in notifier.state)
                            if (current != category) current,
                        };
                      },
                    ),
                  if (selectedCategories.length > 3)
                    Chip(
                      label: Text('+${selectedCategories.length - 3} categorias'),
                    ),
                  if (showMine)
                    const Chip(
                      avatar: Icon(Icons.person, size: 16),
                      label: Text('Meus anúncios'),
                    ),
                  if (sortOption != MarketplaceSortOption.dateDesc)
                    Chip(
                      avatar: const Icon(Icons.sort, size: 16),
                      label: Text(_sortLabel(sortOption)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openAdvancedFilters(
                  context,
                  ref,
                  canShowMineToggle: canShowMineToggle,
                ),
                icon: const Icon(Icons.tune),
                label: const Text('Opções avançadas'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openAdvancedFilters(
  BuildContext context,
  WidgetRef ref, {
  required bool canShowMineToggle,
}) {
  final categoriesNotifier =
      ref.read(marketplaceCategoryFilterProvider.notifier);
  final sortNotifier = ref.read(marketplaceSortProvider.notifier);
  final showMineNotifier = ref.read(marketplaceShowMineProvider.notifier);

  var localCategories = Set<String>.from(categoriesNotifier.state);
  var localSort = sortNotifier.state;
  var localShowMine = showMineNotifier.state;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          void toggleCategory(String category, bool value) {
            setState(() {
              final next = Set<String>.from(localCategories);
              if (value) {
                next.add(category);
              } else {
                next.remove(category);
              }
              localCategories = next;
            });
            categoriesNotifier.state = localCategories;
          }

          void updateSort(MarketplaceSortOption option) {
            setState(() => localSort = option);
            sortNotifier.state = option;
          }

          void updateShowMine(bool value) {
            setState(() => localShowMine = value);
            showMineNotifier.state = value;
          }

          void clearFilters() {
            setState(() {
              localCategories = {};
              localSort = MarketplaceSortOption.dateDesc;
              localShowMine = false;
            });
            categoriesNotifier.state = {};
            sortNotifier.state = MarketplaceSortOption.dateDesc;
            showMineNotifier.state = false;
          }

          return SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Filtros avançados',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Limpar filtros',
                      icon: const Icon(Icons.refresh),
                      onPressed: clearFilters,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Categorias',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final category in listingCategories)
                      FilterChip(
                        label: Text(category),
                        selected: localCategories.contains(category),
                        onSelected: (value) => toggleCategory(category, value),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MarketplaceSortOption>(
                  // ignore: deprecated_member_use
                  value: localSort,
                  decoration: const InputDecoration(labelText: 'Ordenar por'),
                  items: const [
                    DropdownMenuItem(
                      value: MarketplaceSortOption.dateDesc,
                      child: Text('Data (novos primeiro)'),
                    ),
                    DropdownMenuItem(
                      value: MarketplaceSortOption.priceAsc,
                      child: Text('Preço (menor primeiro)'),
                    ),
                    DropdownMenuItem(
                      value: MarketplaceSortOption.priceDesc,
                      child: Text('Preço (maior primeiro)'),
                    ),
                    DropdownMenuItem(
                      value: MarketplaceSortOption.titleAsc,
                      child: Text('Título (A-Z)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      updateSort(value);
                    }
                  },
                ),
                if (canShowMineToggle) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: localShowMine,
                    title: const Text('Mostrar apenas meus anúncios'),
                    onChanged: (value) => updateShowMine(value ?? false),
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(Icons.check),
                    label: const Text('Concluir'),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _sortLabel(MarketplaceSortOption option) {
  switch (option) {
    case MarketplaceSortOption.dateDesc:
      return 'Data (novos)';
    case MarketplaceSortOption.priceAsc:
      return 'Preço (menor)';
    case MarketplaceSortOption.priceDesc:
      return 'Preço (maior)';
    case MarketplaceSortOption.titleAsc:
      return 'Título (A-Z)';
  }
}

class _ListingCard extends ConsumerWidget {
  const _ListingCard({
    required this.listing,
    required this.isOwner,
    required this.isAdmin,
    required this.currencyFormat,
  });

  final Listing listing;
  final bool isOwner;
  final bool isAdmin;
  final NumberFormat currencyFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canEdit = isAdmin || (isOwner && listing.canEdit);
    final canPublish = isAdmin || isOwner;
    final canDelete = isAdmin || (isOwner && listing.status != ListingStatus.sold);
    final coverPhoto = listing.photos.isNotEmpty ? listing.photos.first : null;
    final priceText = listing.price != null
        ? currencyFormat.format(listing.price)
        : 'Sob consulta';
    final statusLabel = _statusLabel(listing.status);
    final statusColor = _statusColor(context, listing.status);
    final paymentLabels = listing.paymentOptions
        .map((option) => paymentOptionLabels[option] ?? option)
        .take(2)
        .toList();

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ListingDetailPage(listing: listing),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverPhoto == null
                        ? Container(
                            width: 96,
                            height: 96,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Icon(Icons.directions_boat_filled),
                          )
                        : Image.network(
                            coverPhoto.publicUrl,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 96,
                              height: 96,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: const Icon(Icons.directions_boat_filled),
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Chip(
                              label: Text(statusLabel),
                              backgroundColor: statusColor,
                            ),
                            Chip(
                              label: Text(listing.category),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          listing.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$priceText • ${_conditionLabel(listing.condition)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (listing.city != null && listing.state != null)
                              '${listing.city}/${listing.state}',
                            'Publicado por ${listing.advertiserName ?? listing.ownerName ?? 'Anunciante'}',
                            DateFormat('dd/MM/yyyy').format(listing.createdAt),
                          ].join(' • '),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  if (canEdit || canPublish || canDelete)
                    PopupMenuButton<_ListingAction>(
                      onSelected: (action) => _handleAction(
                        context,
                        ref,
                        action,
                        canEdit: canEdit,
                        canPublish: canPublish,
                        canDelete: canDelete,
                      ),
                      itemBuilder: (context) => [
                        if (canEdit)
                          const PopupMenuItem(
                            value: _ListingAction.edit,
                            child: Text('Editar'),
                          ),
                        if (canPublish && listing.status == ListingStatus.pending)
                          const PopupMenuItem(
                            value: _ListingAction.publish,
                            child: Text('Publicar'),
                          ),
                        if (canPublish && listing.status == ListingStatus.published)
                          const PopupMenuItem(
                            value: _ListingAction.unpublish,
                            child: Text('Retirar da lista'),
                          ),
                        if (canPublish && !listing.isSold)
                          const PopupMenuItem(
                            value: _ListingAction.markSold,
                            child: Text('Informar venda'),
                          ),
                        if (canDelete)
                          const PopupMenuItem(
                            value: _ListingAction.delete,
                            child: Text('Remover'),
                          ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                listing.description ?? 'Sem descrição detalhada.',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final label in paymentLabels)
                    Chip(
                      label: Text(label),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (listing.whatsappContacts.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.chat, size: 18),
                      label: Text(
                        '${listing.whatsappContacts.length} contato(s)',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    _ListingAction action, {
    required bool canEdit,
    required bool canPublish,
    required bool canDelete,
  }) async {
    switch (action) {
      case _ListingAction.edit:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ListingFormPage(listing: listing),
          ),
        );
        break;
      case _ListingAction.publish:
        if (canPublish) {
          await publishListing(context, ref, listing);
        }
        break;
      case _ListingAction.unpublish:
        if (canPublish) {
          await unpublishListing(context, ref, listing);
        }
        break;
      case _ListingAction.markSold:
        if (canPublish && !listing.isSold) {
          await markListingAsSold(context, ref, listing);
        }
        break;
      case _ListingAction.delete:
        if (canDelete) {
          await deleteListing(context, ref, listing);
        }
        break;
    }
  }
}

enum _ListingAction { edit, publish, unpublish, markSold, delete }

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory, size: 72),
            const SizedBox(height: 12),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case ListingStatus.published:
      return 'Publicado';
    case ListingStatus.sold:
      return 'Vendido';
    default:
      return 'Aguardando';
  }
}

Color _statusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case ListingStatus.published:
      return scheme.secondaryContainer;
    case ListingStatus.sold:
      return scheme.surfaceContainerHighest;
    default:
      return scheme.tertiaryContainer;
  }
}

String _conditionLabel(String condition) {
  switch (condition) {
    case ListingCondition.newItem:
      return 'Novo';
    case ListingCondition.used:
    default:
      return 'Usado';
  }
}
