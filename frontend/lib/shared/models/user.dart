class UserModel {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final int streakDays;
  final int longestStreak;
  final int totalXp;
  final int level;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.streakDays,
    required this.longestStreak,
    required this.totalXp,
    required this.level,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      avatarUrl: json['avatar_url'] as String?,
      streakDays: json['streak_days'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      totalXp: json['total_xp'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'avatar_url': avatarUrl,
      'streak_days': streakDays,
      'longest_streak': longestStreak,
      'total_xp': totalXp,
      'level': level,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
