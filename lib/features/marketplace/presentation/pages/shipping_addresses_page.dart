import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/app_toast.dart';
import '../../../../shared/widgets/error_mapper.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// Shipping addresses CRUD page - full Supabase backend
class ShippingAddressesPage extends ConsumerStatefulWidget {
  const ShippingAddressesPage({super.key});
  @override
  ConsumerState<ShippingAddressesPage> createState() => _ShippingAddressesPageState();
}

class _ShippingAddressesPageState extends ConsumerState<ShippingAddressesPage> {
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAddresses());
  }

  Future<void> _loadAddresses() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await Supabase.instance.client
          .from('user_addresses')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _addresses = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _setDefault(String addressId) async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;

    try {
      // Unset all defaults
      await Supabase.instance.client
          .from('user_addresses')
          .update({'is_default': false})
          .eq('user_id', userId);

      // Set new default
      await Supabase.instance.client
          .from('user_addresses')
          .update({'is_default': true})
          .eq('id', addressId);

      await _loadAddresses();
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  Future<void> _deleteAddress(String addressId) async {
    final c = AlsamosColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: const Text('Manzilni o\'chirish?'),
        content: const Text('Bu amalni bekor qilib bo\'lmaydi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bekor')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('O\'chirish'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await Supabase.instance.client
          .from('user_addresses')
          .delete()
          .eq('id', addressId);

      await _loadAddresses();
      if (!mounted) return;
      AppToast.success(context, 'Manzil o\'chirildi');
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, friendlyError(e));
    }
  }

  void _showAddEditDialog({Map<String, dynamic>? address}) {
    final c = AlsamosColors.of(context);
    final isEdit = address != null;

    final labelCtrl = TextEditingController(text: address?['label'] ?? '');
    final fullNameCtrl = TextEditingController(text: address?['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: address?['phone'] ?? '');
    final addressLineCtrl = TextEditingController(text: address?['address_line'] ?? '');
    final cityCtrl = TextEditingController(text: address?['city'] ?? '');
    final stateCtrl = TextEditingController(text: address?['state'] ?? '');
    final postalCodeCtrl = TextEditingController(text: address?['postal_code'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(isEdit ? 'Manzilni tahrirlash' : 'Yangi manzil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'Yorliq (Uy, Ish, ...)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fullNameCtrl,
                decoration: const InputDecoration(labelText: 'To\'liq ism', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Telefon', border: OutlineInputBorder()),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressLineCtrl,
                decoration: const InputDecoration(labelText: 'Manzil', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cityCtrl,
                decoration: const InputDecoration(labelText: 'Shahar', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stateCtrl,
                decoration: const InputDecoration(labelText: 'Viloyat', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: postalCodeCtrl,
                decoration: const InputDecoration(labelText: 'Pochta indeksi', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Bekor'),
          ),
          FilledButton(
            onPressed: () async {
              if (labelCtrl.text.isEmpty || addressLineCtrl.text.isEmpty) {
                AppToast.info(context, 'Yorliq va manzil majburiy');
                return;
              }

              final userId = ref.read(authProvider).user?.id;
              if (userId == null) return;

              final data = {
                'user_id': userId,
                'label': labelCtrl.text,
                'full_name': fullNameCtrl.text,
                'phone': phoneCtrl.text,
                'address_line': addressLineCtrl.text,
                'city': cityCtrl.text,
                'state': stateCtrl.text,
                'postal_code': postalCodeCtrl.text,
                'is_default': _addresses.isEmpty,
              };

              try {
                if (isEdit) {
                  await Supabase.instance.client
                      .from('user_addresses')
                      .update(data)
                      .eq('id', address['id']);
                } else {
                  await Supabase.instance.client
                      .from('user_addresses')
                      .insert(data);
                }

                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await _loadAddresses();
                if (!mounted) return;
                AppToast.success(context, isEdit ? 'Manzil yangilandi' : 'Manzil qo\'shildi');
              } catch (e) {
                if (!ctx.mounted) return;
                AppToast.error(context, friendlyError(e));
              }
            },
            child: Text(isEdit ? 'Saqlash' : 'Qo\'shish'),
          ),
        ],
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
        title: const Text(
          'Yetkazib berish manzillari',
          style: TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.alertCircle, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Xato: $_error', style: TextStyle(color: c.mutedForeground)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadAddresses,
                        icon: const Icon(LucideIcons.refreshCw, size: 18),
                        label: const Text('Qayta urinish'),
                      ),
                    ],
                  ),
                )
              : _addresses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.mapPin, size: 64, color: c.mutedForeground),
                          const SizedBox(height: 16),
                          Text(
                            'Manzillar yo\'q',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Yetkazib berish uchun manzil qo\'shing',
                            style: TextStyle(color: c.mutedForeground),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, idx) {
                        final addr = _addresses[idx];
                        final isDefault = addr['is_default'] == true;

                        return Container(
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isDefault ? primary : c.border, width: isDefault ? 2 : 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: (isDefault ? primary : c.mutedForeground).withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    LucideIcons.mapPin,
                                    color: isDefault ? primary : c.mutedForeground,
                                    size: 20,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        addr['label'] ?? 'Manzil',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                      ),
                                    ),
                                    if (isDefault)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: primary.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Standart',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primary),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (addr['full_name'] != null && addr['full_name'].toString().isNotEmpty)
                                      Text(addr['full_name'], style: TextStyle(color: c.foreground, fontSize: 13)),
                                    if (addr['phone'] != null && addr['phone'].toString().isNotEmpty)
                                      Text(addr['phone'], style: TextStyle(color: c.mutedForeground, fontSize: 12)),
                                    Text(
                                      '${addr['address_line']}, ${addr['city'] ?? ''}, ${addr['state'] ?? ''} ${addr['postal_code'] ?? ''}'.trim(),
                                      style: TextStyle(color: c.mutedForeground, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Divider(height: 1, color: c.border),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    if (!isDefault)
                                      TextButton.icon(
                                        onPressed: () => _setDefault(addr['id']),
                                        icon: const Icon(LucideIcons.check, size: 16),
                                        label: const Text('Standart qilish'),
                                      ),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: () => _showAddEditDialog(address: addr),
                                      icon: Icon(LucideIcons.edit2, size: 18, color: c.mutedForeground),
                                      tooltip: 'Tahrirlash',
                                    ),
                                    IconButton(
                                      onPressed: () => _deleteAddress(addr['id']),
                                      icon: const Icon(LucideIcons.trash2, size: 18, color: Colors.red),
                                      tooltip: 'O\'chirish',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEditDialog,
        icon: const Icon(LucideIcons.plus, size: 20),
        label: const Text('Manzil qo\'shish'),
      ),
    );
  }
}
