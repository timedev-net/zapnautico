import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/marina_repository.dart';
import 'domain/marina.dart';

final marinasProvider = FutureProvider<List<Marina>>((ref) {
  return ref.watch(marinaRepositoryProvider).fetchMarinas();
});

final marinaFutureProvider =
    FutureProvider.family<Marina?, String>((ref, id) async {
  final marinas = await ref.watch(marinasProvider.future);
  for (final marina in marinas) {
    if (marina.id == id) {
      return marina;
    }
  }
  return ref.watch(marinaRepositoryProvider).fetchById(id);
});
