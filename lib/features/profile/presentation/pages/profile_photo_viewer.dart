import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/profile_provider.dart';

class ProfilePhotoViewer extends ConsumerStatefulWidget {
  final String userId;
  final String? initialAvatarUrl;

  const ProfilePhotoViewer({
    super.key,
    required this.userId,
    this.initialAvatarUrl,
  });

  @override
  ConsumerState<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends ConsumerState<ProfilePhotoViewer> {
  late PageController _pageCtrl;
  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _fetchPhotos();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchPhotos() async {
    try {
      final supabase = Supabase.instance.client;
      final data = await supabase
          .from('profile_photo_history')
          .select()
          .eq('user_id', widget.userId)
          .order('uploaded_at', ascending: false);
      
      if (!mounted) return;
      setState(() {
        _photos = List<Map<String, dynamic>>.from(data);
        if (_photos.isEmpty && widget.initialAvatarUrl != null) {
          // Fallback to initial if table is empty (e.g. before backfill)
          _photos = [
            {'id': 'dummy', 'photo_url': widget.initialAvatarUrl, 'is_current': true}
          ];
        }
        
        // Find index of current avatar to start at
        _currentIndex = 0;
        for (int i = 0; i < _photos.length; i++) {
          if (_photos[i]['is_current'] == true || _photos[i]['photo_url'] == widget.initialAvatarUrl) {
            _currentIndex = i;
            break;
          }
        }
        _loading = false;
      });
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageCtrl.hasClients) {
          _pageCtrl.jumpToPage(_currentIndex);
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _setAsCurrent(Map<String, dynamic> photo) async {
    try {
      final supabase = Supabase.instance.client;
      
      // 1. Update history flags
      await supabase.rpc('set_current_profile_photo', params: {
        'p_user_id': widget.userId,
        'p_photo_id': photo['id'],
        'p_photo_url': photo['photo_url']
      });
      // Fallback if RPC doesn't exist: do it in multiple queries
      // We will create the RPC in the migration to make it atomic.

      if (mounted) {
        ref.invalidate(profileProvider(widget.userId));
        ref.invalidate(authProvider);
        AppToast.success(context, 'Joriy rasm yangilandi');
        _fetchPhotos();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _deletePhoto(Map<String, dynamic> photo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rasmni o\'chirish'),
        content: const Text('Rostdan ham bu rasmni o\'chirmoqchimisiz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('O\'chirish', style: TextStyle(color: Colors.red))),
        ],
      )
    );
    if (ok != true) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('profile_photo_history').delete().eq('id', photo['id']);
      
      if (photo['is_current'] == true) {
        // If we deleted the current one, we should pick the next most recent
        final next = _photos.where((p) => p['id'] != photo['id']).firstOrNull;
        if (next != null) {
          await _setAsCurrent(next);
        } else {
          // No photos left
          await supabase.from('profiles').update({'avatar_url': null}).eq('id', widget.userId);
          if (mounted) {
            ref.invalidate(profileProvider(widget.userId));
            ref.invalidate(authProvider);
          }
        }
      }
      
      if (mounted) {
        AppToast.success(context, 'Rasm o\'chirildi');
        _fetchPhotos();
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwn = ref.watch(authProvider).user?.id == widget.userId;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: _photos.isNotEmpty
            ? Text(
                '${_currentIndex + 1} / ${_photos.length}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : const SizedBox(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _photos.isEmpty
              ? const Center(child: Text('Rasm yo\'q', style: TextStyle(color: Colors.white)))
              : PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemCount: _photos.length,
                  itemBuilder: (ctx, i) {
                    final photo = _photos[i];
                    return InteractiveViewer(
                      child: Center(
                        child: CachedNetworkImage(
                          imageUrl: photo['photo_url'],
                          fit: BoxFit.contain,
                          placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(color: Colors.white)),
                          errorWidget: (context, url, error) => const Center(
                              child: Icon(LucideIcons.imageOff, color: Colors.white54, size: 48)),
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: isOwn && _photos.isNotEmpty ? SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
          color: Colors.black.withValues(alpha: 0.6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_photos[_currentIndex]['is_current'] != true)
                Flexible(
                  child: TextButton.icon(
                    onPressed: () => _setAsCurrent(_photos[_currentIndex]),
                    icon: const Icon(LucideIcons.checkCircle2, color: Colors.white),
                    label: const Text('Asosiy qilish', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white)),
                  ),
                )
              else
                const Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Joriy rasm', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white54)),
                  ),
                ),
              Flexible(
                child: TextButton.icon(
                  onPressed: () => _deletePhoto(_photos[_currentIndex]),
                  icon: const Icon(LucideIcons.trash2, color: Colors.redAccent),
                  label: const Text('O\'chirish', overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ],
          ),
        ),
      ) : null,
    );
  }
}
