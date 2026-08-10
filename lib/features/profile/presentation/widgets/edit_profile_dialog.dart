import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/stories/story_avatar_ring.dart';
import '../../data/username_service.dart';
import '../../data/profile_model.dart';
import '../providers/profile_provider.dart';

/// v23: ports web `SettingsPage.tsx` profile edit form into a dedicated
/// dialog reachable from ProfilePage "Tahrirlash" button.
///
/// Fields: display_name, username, bio, website, location, avatar_url, cover_url.
/// Avatar/cover upload → Supabase Storage `avatars`/`covers` bucket → update profiles row.
class EditProfileDialog extends ConsumerStatefulWidget {
  final FullProfile profile;
  const EditProfileDialog({super.key, required this.profile});

  static Future<void> show(BuildContext context, FullProfile profile) =>
      showDialog(
          context: context,
          builder: (_) => EditProfileDialog(profile: profile));

  @override
  ConsumerState<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends ConsumerState<EditProfileDialog> {
  late final TextEditingController _displayName;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  late final TextEditingController _website;
  late final TextEditingController _location;
  String? _avatarUrl;
  String? _coverUrl;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingCover = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _displayName =
        TextEditingController(text: widget.profile.displayName ?? '');
    _username = TextEditingController(text: widget.profile.username ?? '');
    _bio = TextEditingController(text: widget.profile.bio ?? '');
    _website = TextEditingController(text: widget.profile.website ?? '');
    _location = TextEditingController(text: widget.profile.location ?? '');
    _avatarUrl = widget.profile.avatarUrl;
    _coverUrl = widget.profile.coverUrl;
  }

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _bio.dispose();
    _website.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload({required bool isCover}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: isCover ? 1600 : 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      if (isCover) {
        _uploadingCover = true;
      } else {
        _uploadingAvatar = true;
      }
    });
    try {
      final bucket = isCover ? 'covers' : 'avatars';
      final ext = picked.path.split('.').last.toLowerCase();
      final path =
          '${widget.profile.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await File(picked.path).readAsBytes();
      await Supabase.instance.client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
          );
      final publicUrl =
          Supabase.instance.client.storage.from(bucket).getPublicUrl(path);
      if (!mounted) return;
      setState(() {
        if (isCover) {
          _coverUrl = publicUrl;
        } else {
          _avatarUrl = publicUrl;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Yuklash xatosi: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isCover) {
            _uploadingCover = false;
          } else {
            _uploadingAvatar = false;
          }
        });
      }
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    final usernameService = UsernameService();
    final usernameError = usernameService.validate(username);
    if (usernameError != null) {
      setState(() => _error = usernameError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final normalizedUsername = usernameService.normalize(username);
      final usernameChanged =
          normalizedUsername != (widget.profile.username ?? '').toLowerCase();
      if (usernameChanged) {
        final result = await usernameService.checkAvailability(
          normalizedUsername,
          currentUserId: widget.profile.id,
        );
        if (!result.available) {
          throw Exception(result.localizedMessage ?? 'Username band');
        }
        await usernameService.changeUsername(normalizedUsername);
      }
      await Supabase.instance.client.from('profiles').update({
        'display_name':
            _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'website': _website.text.trim().isEmpty ? null : _website.text.trim(),
        'location':
            _location.text.trim().isEmpty ? null : _location.text.trim(),
        'avatar_url': _avatarUrl,
        'cover_url': _coverUrl,
      }).eq('id', widget.profile.id);
      if (!mounted) return;
      ref.invalidate(profileProvider);
      Navigator.pop(context);
      AppToast.success(context, 'Profil yangilandi');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Saqlash xatosi: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return Dialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Cover area
                Stack(children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    child: Container(
                      height: 130,
                      width: double.infinity,
                      color: c.muted,
                      child: _coverUrl != null
                          ? CachedNetworkImage(
                              imageUrl: _coverUrl!, fit: BoxFit.cover)
                          : Container(
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [
                                  primary.withValues(alpha: 0.6),
                                  primary.withValues(alpha: 0.2)
                                ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight))),
                    ),
                  ),
                  Positioned(
                      right: 10,
                      top: 10,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _uploadingCover
                              ? null
                              : () => _pickAndUpload(isCover: true),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: _uploadingCover
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(LucideIcons.camera,
                                    color: Colors.white, size: 18),
                          ),
                        ),
                      )),
                  Positioned(
                      left: 16,
                      bottom: -32,
                      child: Stack(children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: c.card,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.card, width: 4),
                          ),
                          child: ClipOval(
                              child: StoryAvatarRing(
                                  userId: widget.profile.id,
                                  avatarUrl: _avatarUrl,
                                  size: 72,
                                  fallback: widget.profile.initial)),
                        ),
                        Positioned(
                            right: 0,
                            bottom: 0,
                            child: Material(
                              color: primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _uploadingAvatar
                                    ? null
                                    : () => _pickAndUpload(isCover: false),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: _uploadingAvatar
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : const Icon(LucideIcons.camera,
                                          color: Colors.white, size: 12),
                                ),
                              ),
                            )),
                      ])),
                  Positioned(
                      right: 6,
                      top: 6,
                      child: Material(
                        color: Colors.transparent,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(LucideIcons.x,
                              color: Colors.white, size: 18),
                        ),
                      )),
                ]),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(c, "Ism"),
                        _field(c, _displayName, hint: 'Ismingiz'),
                        const SizedBox(height: 12),
                        _label(c, "Username"),
                        _field(c, _username, hint: 'username', prefix: '@'),
                        const SizedBox(height: 12),
                        _label(c, "Bio"),
                        _field(c, _bio,
                            hint: "O'zingiz haqida...",
                            maxLines: 3,
                            maxLength: 160),
                        const SizedBox(height: 12),
                        _label(c, "Veb-sayt"),
                        _field(c, _website, hint: 'https://...'),
                        const SizedBox(height: 12),
                        _label(c, "Joylashuv"),
                        _field(c, _location, hint: 'Toshkent, O\'zbekiston'),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFEF4444), fontSize: 12)),
                        ],
                        const SizedBox(height: 18),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton(
                            onPressed:
                                _saving ? null : () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12)),
                            child: const Text('Bekor qilish'),
                          )),
                          const SizedBox(width: 10),
                          Expanded(
                              child: FilledButton(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12)),
                            child: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Saqlash',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                          )),
                        ]),
                      ]),
                ),
              ]),
        ),
      ),
    );
  }

  Widget _label(AlsamosColors c, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                color: c.mutedForeground,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      );

  Widget _field(AlsamosColors c, TextEditingController controller,
      {String? hint, String? prefix, int maxLines = 1, int? maxLength}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefix,
        isDense: true,
        filled: true,
        fillColor: c.muted,
        counterText: '',
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
    );
  }
}
