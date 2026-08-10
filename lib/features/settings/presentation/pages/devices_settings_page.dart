import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Devices settings: Telegram-grade session management with current device,
/// active sessions list, per-session detail, auto-terminate, and edit mode
class DevicesSettingsPage extends ConsumerStatefulWidget {
  const DevicesSettingsPage({super.key});
  @override
  ConsumerState<DevicesSettingsPage> createState() =>
      _DevicesSettingsPageState();
}

class _DevicesSettingsPageState extends ConsumerState<DevicesSettingsPage> {
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _currentSession;
  bool _loading = true;
  bool _editMode = false;
  int _autoTerminateDays = 180; // 6 months default

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    await Future.wait([_loadSessions(), _loadAutoTerminatePeriod()]);
  }

  Future<void> _loadSessions() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('user_sessions')
          .select('*')
          .eq('user_id', userId)
          .order('last_active_at', ascending: false);

      if (!mounted) return;

      final sessions = List<Map<String, dynamic>>.from(data);
      setState(() {
        _currentSession = sessions.firstWhere(
          (s) => s['is_current'] == true,
          orElse: () => sessions.isNotEmpty ? sessions.first : {},
        );
        _sessions = sessions.where((s) => s['is_current'] != true).toList();
      });
    } catch (e) {
      debugPrint('Load sessions error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAutoTerminatePeriod() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    try {
      final data = await Supabase.instance.client
          .from('user_settings')
          .select('session_autoterminate_days')
          .eq('user_id', userId)
          .maybeSingle();

      if (!mounted) return;
      if (data != null && data['session_autoterminate_days'] != null) {
        setState(() =>
            _autoTerminateDays = data['session_autoterminate_days'] as int);
      }
    } catch (e) {
      debugPrint('Load auto-terminate period error: $e');
    }
  }

  Future<void> _updateAutoTerminatePeriod(int days) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client
          .from('user_settings')
          .update({'session_autoterminate_days': days}).eq('user_id', userId);

      setState(() => _autoTerminateDays = days);
      if (mounted) {
        AppToast.success(context, AppStrings.of(ref).t('common.done'));
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _terminateSession(String sessionId) async {
    final confirmed = await _showConfirmDialog(
      'Seansni tugatish?',
      'Ushbu qurilmadan chiqarilasiz',
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('user_sessions')
          .delete()
          .eq('id', sessionId);

      await _loadSessions();
      if (mounted) {
        AppToast.success(context, 'Seans tugatildi');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _terminateAllOtherSessions() async {
    final confirmed = await _showConfirmDialog(
      'Boshqa barcha seanslarni tugatish?',
      'Bu qurilmadan tashqari barcha qurilmalardan chiqib ketiladi',
    );
    if (confirmed != true) return;

    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client
          .from('user_sessions')
          .delete()
          .eq('user_id', userId)
          .neq('is_current', true);

      await _loadSessions();
      if (mounted) {
        AppToast.success(context, 'Barcha boshqa seanslar tugatildi');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<void> _updateSessionToggles(String sessionId,
      {bool? acceptSecretChats, bool? acceptIncomingCalls}) async {
    try {
      final updates = <String, dynamic>{};
      if (acceptSecretChats != null) {
        updates['accept_secret_chats'] = acceptSecretChats;
      }
      if (acceptIncomingCalls != null) {
        updates['accept_incoming_calls'] = acceptIncomingCalls;
      }

      await Supabase.instance.client
          .from('user_sessions')
          .update(updates)
          .eq('id', sessionId);

      await _loadSessions();
    } catch (e) {
      if (mounted) {
        AppToast.error(context, friendlyError(e));
      }
    }
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    final c = AlsamosColors.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title),
        content: Text(content, style: TextStyle(color: c.mutedForeground)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tasdiqlash'),
          ),
        ],
      ),
    );
  }

  void _showSessionDetail(Map<String, dynamic> session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SessionDetailSheet(
        session: session,
        onTerminate: () {
          Navigator.pop(context);
          _terminateSession(session['id'].toString());
        },
        onToggleSecretChats: (value) {
          _updateSessionToggles(session['id'].toString(),
              acceptSecretChats: value);
        },
        onToggleIncomingCalls: (value) {
          _updateSessionToggles(session['id'].toString(),
              acceptIncomingCalls: value);
        },
      ),
    );
  }

  void _showAutoTerminatePicker() {
    final c = AlsamosColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'Nofaollik muddati',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            ...[
              (7, '1 hafta'),
              (30, '1 oy'),
              (90, '3 oy'),
              (180, '6 oy'),
              (365, '1 yil'),
            ].map((item) {
              final selected = _autoTerminateDays == item.$1;
              return ListTile(
                title: Text(item.$2),
                trailing: selected
                    ? Icon(LucideIcons.check,
                        color: Theme.of(context).colorScheme.primary, size: 20)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _updateAutoTerminatePeriod(item.$1);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 22),
        ),
        title: Text(
          AppStrings.of(ref).t('settings.items.devices'),
          style: const TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_sessions.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _editMode = !_editMode),
              child: Text(_editMode ? 'Tayyor' : 'Tahrirlash'),
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primary))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Section 1: Current device
                  _sectionHeader('BU QURILMA', c),
                  if (_currentSession != null) ...[
                    _buildCurrentDeviceCard(_currentSession!, c, primary),
                    const SizedBox(height: 12),
                    if (_sessions.isNotEmpty) _buildTerminateAllCard(c),
                  ],

                  // Section 2: Active sessions
                  if (_sessions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _sectionHeader('FAOL SEANSLAR', c),
                    ..._sessions.map((session) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildSessionCard(session, c, primary),
                        )),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'Rasmiy Alsamos ilovalari barcha platformalarda mavjud',
                        style: TextStyle(
                          fontSize: 11,
                          color: c.mutedForeground,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],

                  // Section 3: Auto-terminate
                  const SizedBox(height: 24),
                  _sectionHeader('ESKI SEANSLARNI AVTOMATIK TUGATISH', c),
                  _buildAutoTerminateCard(c),

                  // Empty state
                  if (_currentSession == null && _sessions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          children: [
                            Icon(LucideIcons.smartphone,
                                size: 48, color: c.mutedForeground),
                            const SizedBox(height: 16),
                            Text(
                              'Hozircha sessiyalar yo\'q',
                              style: TextStyle(
                                color: c.foreground,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String text, AlsamosColors c) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10, top: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.mutedForeground,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _buildCurrentDeviceCard(
      Map<String, dynamic> session, AlsamosColors c, Color primary) {
    final platform = session['platform']?.toString() ?? 'unknown';
    final deviceName = session['device_name']?.toString() ??
        session['device_model']?.toString() ??
        'Bu qurilma';
    final appInfo =
        '${session['app_name'] ?? 'Alsamos'} ${session['app_version'] ?? ''} ${session['os_version'] ?? ''}'
            .trim();
    final location = _formatLocation(session);
    final (icon, color) = _getPlatformIconColor(platform);

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appInfo,
                      style: TextStyle(fontSize: 12, color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'onlayn',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF22C55E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(LucideIcons.mapPin, size: 14, color: c.mutedForeground),
                const SizedBox(width: 6),
                Text(
                  location,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTerminateAllCard(AlsamosColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(LucideIcons.logOut,
              color: Color(0xFFEF4444), size: 18),
        ),
        title: const Text(
          'Boshqa barcha seanslarni tugatish',
          style: TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w600,
              fontSize: 14),
        ),
        subtitle: Text(
          'Bu qurilmadan tashqari barcha qurilmalardan chiqib ketiladi',
          style: TextStyle(color: c.mutedForeground, fontSize: 11),
        ),
        trailing: const Icon(LucideIcons.chevronRight,
            color: Color(0xFFEF4444), size: 18),
        onTap: _terminateAllOtherSessions,
      ),
    );
  }

  Widget _buildSessionCard(
      Map<String, dynamic> session, AlsamosColors c, Color primary) {
    final platform = session['platform']?.toString() ?? 'unknown';
    final deviceName = session['device_name']?.toString() ??
        session['device_model']?.toString() ??
        'Noma\'lum qurilma';
    final appInfo =
        '${session['app_name'] ?? 'Alsamos'} ${session['app_version'] ?? ''}'
            .trim();
    final location = _formatLocation(session);
    final lastActive = _formatLastActive(session['last_active_at']);
    final (icon, color) = _getPlatformIconColor(platform);

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          deviceName,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              appInfo,
              style: TextStyle(fontSize: 12, color: c.mutedForeground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (location.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '$location • $lastActive',
                style: TextStyle(fontSize: 11, color: c.mutedForeground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: _editMode
            ? IconButton(
                onPressed: () => _terminateSession(session['id'].toString()),
                icon: const Icon(LucideIcons.trash2,
                    color: Color(0xFFEF4444), size: 18),
              )
            : Icon(LucideIcons.chevronRight,
                color: c.mutedForeground, size: 18),
        onTap: _editMode ? null : () => _showSessionDetail(session),
      ),
    );
  }

  Widget _buildAutoTerminateCard(AlsamosColors c) {
    final periodText = _autoTerminateDays == 7
        ? '1 hafta'
        : _autoTerminateDays == 30
            ? '1 oy'
            : _autoTerminateDays == 90
                ? '3 oy'
                : _autoTerminateDays == 180
                    ? '6 oy'
                    : '1 yil';

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: ListTile(
        leading: Icon(LucideIcons.clock, color: c.mutedForeground, size: 20),
        title: const Text('Nofaollik muddati', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          'Eski seanslar avtomatik tugatiladi',
          style: TextStyle(fontSize: 11, color: c.mutedForeground),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              periodText,
              style: TextStyle(fontSize: 13, color: c.mutedForeground),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.chevronRight, color: c.mutedForeground, size: 18),
          ],
        ),
        onTap: _showAutoTerminatePicker,
      ),
    );
  }

  String _formatLocation(Map<String, dynamic> session) {
    final city = session['location_city']?.toString() ?? '';
    final country = session['location_country']?.toString() ?? '';
    if (city.isNotEmpty && country.isNotEmpty) return '$city, $country';
    if (city.isNotEmpty) return city;
    if (country.isNotEmpty) return country;
    return '';
  }

  String _formatLastActive(dynamic lastActiveAt) {
    if (lastActiveAt == null) return 'Noma\'lum';

    try {
      final dt = DateTime.parse(lastActiveAt.toString());
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inSeconds < 60) return 'hozirgina';
      if (diff.inMinutes < 60) return '${diff.inMinutes} daqiqa oldin';
      if (diff.inHours < 24) return '${diff.inHours} soat oldin';
      if (diff.inDays < 7) return '${diff.inDays} kun oldin';

      // For older dates, show formatted date
      return DateFormat('dd/MM/yy').format(dt);
    } catch (e) {
      return 'Noma\'lum';
    }
  }

  (IconData, Color) _getPlatformIconColor(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('ios') || p.contains('iphone') || p.contains('ipad')) {
      return (LucideIcons.smartphone, const Color(0xFF3B82F6)); // Blue
    } else if (p.contains('android')) {
      return (LucideIcons.smartphone, const Color(0xFF22C55E)); // Green
    } else if (p.contains('windows') || p.contains('desktop')) {
      return (LucideIcons.laptop, const Color(0xFF3B82F6)); // Blue
    } else if (p.contains('web') ||
        p.contains('macos') ||
        p.contains('linux')) {
      return (LucideIcons.globe, const Color(0xFFA855F7)); // Purple
    }
    return (LucideIcons.monitor, const Color(0xFF64748B)); // Gray default
  }
}

// Session Detail Bottom Sheet
class _SessionDetailSheet extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTerminate;
  final ValueChanged<bool> onToggleSecretChats;
  final ValueChanged<bool> onToggleIncomingCalls;

  const _SessionDetailSheet({
    required this.session,
    required this.onTerminate,
    required this.onToggleSecretChats,
    required this.onToggleIncomingCalls,
  });

  @override
  State<_SessionDetailSheet> createState() => _SessionDetailSheetState();
}

class _SessionDetailSheetState extends State<_SessionDetailSheet> {
  late bool _acceptSecretChats;
  late bool _acceptIncomingCalls;

  @override
  void initState() {
    super.initState();
    _acceptSecretChats = widget.session['accept_secret_chats'] == true;
    _acceptIncomingCalls = widget.session['accept_incoming_calls'] == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final platform = widget.session['platform']?.toString() ?? 'unknown';
    final deviceName = widget.session['device_name']?.toString() ??
        widget.session['device_model']?.toString() ??
        'Noma\'lum qurilma';
    final appName = widget.session['app_name']?.toString() ?? 'Alsamos';
    final appVersion = widget.session['app_version']?.toString() ?? '';
    final city = widget.session['location_city']?.toString() ?? '';
    final country = widget.session['location_country']?.toString() ?? '';
    final location = city.isNotEmpty && country.isNotEmpty
        ? '$city, $country'
        : (city.isNotEmpty ? city : country);
    final createdAt = widget.session['created_at']?.toString();
    final (icon, color) = _getPlatformIconColor(platform);

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Spacer(),
                  Text(
                    'Seans tafsilotlari',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: c.foreground,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Platform icon + device name
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(icon, color: color, size: 32),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            deviceName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Birinchi ko\'rilgan: ${DateFormat('dd MMM yyyy').format(DateTime.parse(createdAt))}',
                              style: TextStyle(
                                fontSize: 12,
                                color: c.mutedForeground,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info section
                    _DetailRow(
                      label: 'Ilova',
                      value: '$appName $appVersion'.trim(),
                      icon: LucideIcons.smartphone,
                      c: c,
                    ),
                    const SizedBox(height: 12),
                    _DetailRow(
                      label: 'Joylashuv',
                      value: location.isNotEmpty ? location : 'Noma\'lum',
                      icon: LucideIcons.mapPin,
                      c: c,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 32, top: 4),
                      child: Text(
                        'Bu joylashuv IP manzilga asosan taxmin qilinadi va har doim ham aniq bo\'lmasligi mumkin.',
                        style: TextStyle(
                          fontSize: 10,
                          color: c.mutedForeground,
                          height: 1.3,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Accept on this device section
                    Text(
                      'BU QURILMADA QABUL QILISH',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.mutedForeground,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: c.muted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            value: _acceptSecretChats,
                            onChanged: (v) {
                              setState(() => _acceptSecretChats = v);
                              widget.onToggleSecretChats(v);
                            },
                            title: const Text(
                              'Yangi maxfiy chatlar',
                              style: TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              'Ushbu qurilmada maxfiy chatlarni qabul qilish',
                              style: TextStyle(
                                  fontSize: 11, color: c.mutedForeground),
                            ),
                          ),
                          Divider(height: 1, color: c.border),
                          SwitchListTile.adaptive(
                            value: _acceptIncomingCalls,
                            onChanged: (v) {
                              setState(() => _acceptIncomingCalls = v);
                              widget.onToggleIncomingCalls(v);
                            },
                            title: const Text(
                              'Kiruvchi chaqiruvlar',
                              style: TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              'Ushbu qurilmada chaqiruvlarni qabul qilish',
                              style: TextStyle(
                                  fontSize: 11, color: c.mutedForeground),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Terminate button
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: widget.onTerminate,
                        icon: const Icon(LucideIcons.logOut, size: 18),
                        label: const Text('Seansni tugatish'),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color) _getPlatformIconColor(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('ios') || p.contains('iphone') || p.contains('ipad')) {
      return (LucideIcons.smartphone, const Color(0xFF3B82F6));
    } else if (p.contains('android')) {
      return (LucideIcons.smartphone, const Color(0xFF22C55E));
    } else if (p.contains('windows') || p.contains('desktop')) {
      return (LucideIcons.laptop, const Color(0xFF3B82F6));
    } else if (p.contains('web') ||
        p.contains('macos') ||
        p.contains('linux')) {
      return (LucideIcons.globe, const Color(0xFFA855F7));
    }
    return (LucideIcons.monitor, const Color(0xFF64748B));
  }
}

// Detail Row Widget
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final AlsamosColors c;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: c.mutedForeground.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 12, color: c.mutedForeground),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: c.mutedForeground,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
