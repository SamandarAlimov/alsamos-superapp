// Check-in Panel - Create check-ins at places
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/social_map_service.dart';

final _socialMapServiceProvider = Provider((ref) => SocialMapService());

/// Check-in Panel
class CheckInPanel extends ConsumerStatefulWidget {
  final String placeId;
  final String placeName;
  final String? placeCategory;
  final LatLng location;

  const CheckInPanel({
    required this.placeId,
    required this.placeName,
    this.placeCategory,
    required this.location,
    super.key,
  });

  @override
  ConsumerState<CheckInPanel> createState() => _CheckInPanelState();
}

class _CheckInPanelState extends ConsumerState<CheckInPanel> {
  String _visibility = 'friends';
  String? _feeling;
  final _noteController = TextEditingController();
  bool _isLoading = false;

  final _feelings = [
    ('😊', 'happy', 'Xursand'),
    ('😍', 'excited', 'Hayajonli'),
    ('😌', 'relaxed', 'Xotirjam'),
    ('🤤', 'hungry', 'Och'),
    ('😴', 'tired', 'Charchagan'),
    ('🤩', 'amazed', 'Hayratda'),
    ('😎', 'cool', 'Zo\'r'),
    ('🥳', 'celebrating', 'Bayram'),
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitCheckIn() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final service = ref.read(_socialMapServiceProvider);
      final currentUser = Supabase.instance.client.auth.currentUser;

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final checkIn = CheckIn(
        id: '',
        userId: currentUser.id,
        placeId: widget.placeId,
        placeName: widget.placeName,
        placeCategory: widget.placeCategory,
        location: widget.location,
        feeling: _feeling,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        visibility: _visibility,
        createdAt: DateTime.now(),
      );

      await service.createCheckIn(checkIn);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Check-in yaratildi ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xatolik: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.mapPin, color: primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.placeName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: c.foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.placeCategory != null)
                        Text(
                          widget.placeCategory!,
                          style: TextStyle(
                            fontSize: 12,
                            color: c.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.x),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: c.border),

          // Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Feeling
                  Text(
                    'Kayfiyat',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _feelings.map((f) {
                      final isSelected = _feeling == f.$2;
                      return InkWell(
                        onTap: () => setState(() =>
                            _feeling = isSelected ? null : f.$2),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primary.withValues(alpha: 0.15)
                                : c.muted,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? primary : c.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(f.$1, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 6),
                              Text(
                                f.$3,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: c.foreground,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  // Note
                  Text(
                    'Eslatma (ixtiyoriy)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Bu joy haqida nimanidir yozing...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: primary, width: 2),
                      ),
                      filled: true,
                      fillColor: c.background,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Visibility
                  Text(
                    'Kim ko\'rishi mumkin',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _VisibilitySelector(
                    value: _visibility,
                    onChanged: (v) => setState(() => _visibility = v),
                    c: c,
                    primary: primary,
                  ),

                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitCheckIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Check-in qilish',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisibilitySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final AlsamosColors c;
  final Color primary;

  const _VisibilitySelector({
    required this.value,
    required this.onChanged,
    required this.c,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      ('public', LucideIcons.globe, 'Hammaga'),
      ('followers', LucideIcons.users, 'Kuzatuvchilar'),
      ('friends', LucideIcons.userCheck, 'Do\'stlar'),
      ('private', LucideIcons.lock, 'Faqat men'),
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = value == opt.$1;
        return Expanded(
          child: InkWell(
            onTap: () => onChanged(opt.$1),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? primary.withValues(alpha: 0.15) : c.muted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? primary : c.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    opt.$2,
                    size: 20,
                    color: isSelected ? primary : c.mutedForeground,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    opt.$3,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? primary : c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
