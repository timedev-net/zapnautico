import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../user_profiles/providers.dart';
import 'data/boat_financial_repository.dart';
import 'domain/boat_expense.dart';

final boatExpensesProvider = FutureProvider.autoDispose
    .family<List<BoatExpense>, String>((ref, boatId) {
      return ref
          .watch(boatFinancialRepositoryProvider)
          .fetchExpenses(boatId: boatId);
    });

final allBoatExpensesProvider = FutureProvider.autoDispose<List<BoatExpense>>(
  (ref) => ref.watch(boatFinancialRepositoryProvider).fetchExpenses(),
);

final canManageFinancialProvider = Provider.autoDispose<bool>((ref) {
  final profiles = ref.watch(currentUserProfilesProvider);
  return profiles.maybeWhen(
    data: (items) => items.any(
      (profile) =>
          profile.profileSlug == 'proprietario' ||
          profile.profileSlug == 'cotista',
    ),
    orElse: () => false,
  );
});
