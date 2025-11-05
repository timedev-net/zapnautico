import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_providers.dart';
import '../domain/profile_models.dart';

class UserProfileRepository {
  UserProfileRepository(this._client);

  final SupabaseClient _client;

  Future<List<ProfileType>> fetchProfileTypes() async {
    final response = await _client
        .from('profile_types')
        .select('slug,name,description')
        .order('name');

    final data = (response as List).cast<Map<String, dynamic>>();
    return data.map(ProfileType.fromMap).toList();
  }

  Future<List<UserProfileAssignment>> fetchProfilesForUser(
    String userId,
  ) async {
    final response = await _client
        .from('user_profiles_view')
        .select(
          'id,user_id,profile_slug,profile_name,assigned_by,created_at,marina_id,marina_name',
        )
        .eq('user_id', userId)
        .order('created_at');

    final data = (response as List).cast<Map<String, dynamic>>();
    return data.map(UserProfileAssignment.fromMap).toList();
  }

  Future<List<UserProfileAssignment>> fetchAllAssignments() async {
    final response = await _client
        .from('user_profiles_view')
        .select(
          'id,user_id,profile_slug,profile_name,assigned_by,created_at,marina_id,marina_name',
        )
        .order('user_id')
        .order('profile_name');

    final data = (response as List).cast<Map<String, dynamic>>();
    return data.map(UserProfileAssignment.fromMap).toList();
  }

  Future<List<AppUser>> adminListUsers() async {
    final response = await _client.rpc('admin_list_users') as List<dynamic>?;

    if (response == null) {
      return [];
    }

    return response.cast<Map<String, dynamic>>().map(AppUser.fromMap).toList();
  }

  Future<void> adminSetUserProfiles({
    required String userId,
    required List<Map<String, dynamic>> profilePayloads,
  }) async {
    await _client.rpc(
      'admin_set_user_profiles',
      params: {'target_user': userId, 'profile_payloads': profilePayloads},
    );
  }

  Future<List<AppUserWithProfiles>> adminFetchUsersWithProfiles() async {
    final users = await adminListUsers();
    final assignments = await fetchAllAssignments();

    final lookup = <String, List<UserProfileAssignment>>{};

    for (final assignment in assignments) {
      lookup.putIfAbsent(assignment.userId, () => []).add(assignment);
    }

    return users
        .map(
          (user) => AppUserWithProfiles(
            user: user,
            profiles: lookup[user.id] ?? const <UserProfileAssignment>[],
          ),
        )
        .toList();
  }
}

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return UserProfileRepository(client);
});
