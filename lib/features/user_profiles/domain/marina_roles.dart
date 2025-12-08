import 'profile_models.dart';

const Set<String> marinaRoleSlugs = {'marina', 'gestor_marina'};

bool isMarinaRoleSlug(String? slug) {
  return slug != null && marinaRoleSlugs.contains(slug);
}

bool hasMarinaRole(Iterable<UserProfileAssignment> profiles) {
  return profiles.any((profile) => isMarinaRoleSlug(profile.profileSlug));
}

UserProfileAssignment? firstMarinaProfile(
  Iterable<UserProfileAssignment> profiles,
) {
  for (final profile in profiles) {
    if (isMarinaRoleSlug(profile.profileSlug) &&
        profile.marinaId != null &&
        profile.marinaId!.isNotEmpty) {
      return profile;
    }
  }
  return null;
}
