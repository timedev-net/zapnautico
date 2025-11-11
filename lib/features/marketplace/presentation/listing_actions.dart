import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/listings_repository.dart';
import '../domain/listing.dart';

Future<void> publishListing(
  BuildContext context,
  WidgetRef ref,
  Listing listing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await ref
      .read(listingsRepositoryProvider)
      .updateListingStatus(id: listing.id, status: ListingStatus.published);
  messenger.showSnackBar(
    const SnackBar(content: Text('Anúncio publicado com sucesso.')),
  );
}

Future<void> unpublishListing(
  BuildContext context,
  WidgetRef ref,
  Listing listing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  await ref
      .read(listingsRepositoryProvider)
      .updateListingStatus(id: listing.id, status: ListingStatus.pending);
  messenger.showSnackBar(
    const SnackBar(content: Text('Anúncio removido da lista pública.')),
  );
}

Future<void> markListingAsSold(
  BuildContext context,
  WidgetRef ref,
  Listing listing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Informar venda'),
        content: const Text(
          'Após confirmar a venda não será possível editar o anúncio. '
          'Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar venda'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  await ref
      .read(listingsRepositoryProvider)
      .updateListingStatus(id: listing.id, status: ListingStatus.sold);

  messenger.showSnackBar(
    const SnackBar(content: Text('Anúncio marcado como vendido.')),
  );
}

Future<void> deleteListing(
  BuildContext context,
  WidgetRef ref,
  Listing listing,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Remover anúncio'),
        content: Text(
          'Confirma a remoção de "${listing.title}"? Esta ação não poderá ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remover'),
          ),
        ],
      );
    },
  );

  if (confirmed != true) {
    return;
  }

  await ref.read(listingsRepositoryProvider).deleteListing(listing);
  messenger.showSnackBar(
    const SnackBar(content: Text('Anúncio removido.')),
  );
}
