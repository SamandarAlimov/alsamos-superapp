/// Ported 1:1 from web `useUserSettings.ts` (user_settings + user_sessions).
class UserSettings {
  final String lastSeenVisibility;
  final bool readReceiptsEnabled;
  final String callPermissions;
  final String groupInvitePermissions;
  final String phoneVisibility;
  final String profilePhotoVisibility;
  final String forwardsVisibility;
  final bool privateAccount;
  final bool twoFactorEnabled;
  final bool notificationSounds;
  final bool notificationPreview;
  final bool notifyLikes;
  final bool notifyComments;
  final bool notifyFollows;
  final bool notifyMentions;
  final bool autoplayVoiceMessages;
  final bool autoplayVideoMessages;

  const UserSettings({
    this.lastSeenVisibility = 'everyone',
    this.readReceiptsEnabled = true,
    this.callPermissions = 'everyone',
    this.groupInvitePermissions = 'everyone',
    this.phoneVisibility = 'contacts',
    this.profilePhotoVisibility = 'everyone',
    this.forwardsVisibility = 'everyone',
    this.privateAccount = false,
    this.twoFactorEnabled = false,
    this.notificationSounds = true,
    this.notificationPreview = true,
    this.notifyLikes = true,
    this.notifyComments = true,
    this.notifyFollows = true,
    this.notifyMentions = true,
    this.autoplayVoiceMessages = true,
    this.autoplayVideoMessages = true,
  });

  factory UserSettings.fromMap(Map<String, dynamic> m) => UserSettings(
        lastSeenVisibility:
            (m['last_seen_visibility'] as String?) ?? 'everyone',
        readReceiptsEnabled: (m['read_receipts_enabled'] as bool?) ?? true,
        callPermissions: (m['call_permissions'] as String?) ?? 'everyone',
        groupInvitePermissions:
            (m['group_invite_permissions'] as String?) ?? 'everyone',
        phoneVisibility: (m['phone_visibility'] as String?) ?? 'contacts',
        profilePhotoVisibility:
            (m['profile_photo_visibility'] as String?) ?? 'everyone',
        forwardsVisibility: (m['forwards_visibility'] as String?) ?? 'everyone',
        privateAccount: (m['private_account'] as bool?) ?? false,
        twoFactorEnabled: (m['two_factor_enabled'] as bool?) ?? false,
        notificationSounds: (m['notification_sounds'] as bool?) ?? true,
        notificationPreview: (m['notification_preview'] as bool?) ?? true,
        notifyLikes: (m['notify_likes'] as bool?) ?? true,
        notifyComments: (m['notify_comments'] as bool?) ?? true,
        notifyFollows: (m['notify_follows'] as bool?) ?? true,
        notifyMentions: (m['notify_mentions'] as bool?) ?? true,
        autoplayVoiceMessages: (m['autoplay_voice_messages'] as bool?) ?? true,
        autoplayVideoMessages: (m['autoplay_video_messages'] as bool?) ?? true,
      );

  UserSettings copyWith(Map<String, dynamic> u) =>
      UserSettings.fromMap({...toMap(), ...u});

  Map<String, dynamic> toMap() => {
        'last_seen_visibility': lastSeenVisibility,
        'read_receipts_enabled': readReceiptsEnabled,
        'call_permissions': callPermissions,
        'group_invite_permissions': groupInvitePermissions,
        'phone_visibility': phoneVisibility,
        'profile_photo_visibility': profilePhotoVisibility,
        'forwards_visibility': forwardsVisibility,
        'private_account': privateAccount,
        'two_factor_enabled': twoFactorEnabled,
        'notification_sounds': notificationSounds,
        'notification_preview': notificationPreview,
        'notify_likes': notifyLikes,
        'notify_comments': notifyComments,
        'notify_follows': notifyFollows,
        'notify_mentions': notifyMentions,
        'autoplay_voice_messages': autoplayVoiceMessages,
        'autoplay_video_messages': autoplayVideoMessages,
      };
}

class UserSession {
  final String id;
  final String? deviceName;
  final String? deviceType;
  final String? osName;
  final String? browserName;
  final String? ipAddress;
  final DateTime? lastActiveAt;
  final bool isCurrent;

  const UserSession({
    required this.id,
    this.deviceName,
    this.deviceType,
    this.osName,
    this.browserName,
    this.ipAddress,
    this.lastActiveAt,
    this.isCurrent = false,
  });

  factory UserSession.fromMap(Map<String, dynamic> m) => UserSession(
        id: m['id'] as String,
        deviceName: m['device_name'] as String?,
        deviceType: m['device_type'] as String?,
        osName: m['os_name'] as String?,
        browserName: m['browser_name'] as String?,
        ipAddress: m['ip_address'] as String?,
        lastActiveAt: m['last_active_at'] != null
            ? DateTime.tryParse(m['last_active_at'] as String)?.toLocal()
            : null,
        isCurrent: (m['is_current'] as bool?) ?? false,
      );

  /// Editable profile fields (from web `profiles` usage in SettingsPage).
}

class EditableProfile {
  final String displayName;
  final String username;
  final String bio;
  final String? avatarUrl;
  final String location;
  final String website;
  final String? country;
  final String? birthDate;

  const EditableProfile({
    this.displayName = '',
    this.username = '',
    this.bio = '',
    this.avatarUrl,
    this.location = '',
    this.website = '',
    this.country,
    this.birthDate,
  });

  factory EditableProfile.fromMap(Map<String, dynamic> m) => EditableProfile(
        displayName: (m['display_name'] as String?) ?? '',
        username: (m['username'] as String?) ?? '',
        bio: (m['bio'] as String?) ?? '',
        avatarUrl: m['avatar_url'] as String?,
        location: (m['location'] as String?) ?? '',
        website: (m['website'] as String?) ?? '',
        country: m['country'] as String?,
        birthDate: m['birth_date'] as String?,
      );
}
