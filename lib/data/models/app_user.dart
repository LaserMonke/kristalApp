import 'education_level.dart';

/// The signed-in learner.
///
/// Deliberately minimal: an id, a display name and an education band. No
/// email, no birthdate, no contact details — CLAUDE.md rule 6 (the audience may
/// include minors, so collect the minimum data needed).
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.educationLevel,
    required this.createdAt,
  });

  final String id;
  final String username;
  final EducationLevel educationLevel;
  final DateTime createdAt;

  AppUser copyWith({String? username, EducationLevel? educationLevel}) {
    return AppUser(
      id: id,
      username: username ?? this.username,
      educationLevel: educationLevel ?? this.educationLevel,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'username': username,
    'education_level': educationLevel.name,
    'created_at': createdAt.toIso8601String(),
  };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      username: json['username'] as String,
      educationLevel: EducationLevel.fromName(
        json['education_level'] as String?,
      ),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// First letter, for the profile avatar.
  String get initial =>
      username.isEmpty ? '?' : username.substring(0, 1).toUpperCase();
}
