// Ported 1:1 from web src/components/marketplace/CreateProductDialog.tsx.
// 10-image grid upload, full form, condition + category pickers.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../providers/marketplace_provider.dart';

class CreateProductSheet extends ConsumerStatefulWidget {
  const CreateProductSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateProductSheet(),
    );
  }

  @override
  ConsumerState<CreateProductSheet> createState() => _CreateProductSheetState();
}

class _CreateProductSheetState extends ConsumerState<CreateProductSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _compareAt = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _shippingPrice = TextEditingController(text: '0');
  final _location = TextEditingController();

  String? _categoryId;
  String _condition = 'new';
  bool _isNegotiable = false;
  bool _shippingAvailable = true;
  bool _submitting = false;
  String? _error;

  final List<XFile> _pickedImages = [];
  final _picker = ImagePicker();

  static const _conditions = [
    ('new', 'Yangi'),
    ('like_new', 'Yangiday'),
    ('good', 'Yaxshi'),
    ('fair', 'Oʼrtacha'),
    ('used', 'Ishlatilgan'),
  ];

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _compareAt.dispose();
    _quantity.dispose();
    _shippingPrice.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remaining = 10 - _pickedImages.length;
    if (remaining <= 0) return;
    final result = await _picker.pickMultiImage(imageQuality: 80, limit: remaining);
    if (result.isEmpty) return;
    setState(() {
      _pickedImages.addAll(result.take(remaining));
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final priceText = _price.text.trim();
    if (title.isEmpty || priceText.isEmpty) {
      setState(() => _error = 'Sarlavha va narx majburiy');
      return;
    }
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      setState(() => _error = 'Narx notoʼgʼri');
      return;
    }
    if (_pickedImages.isEmpty) {
      setState(() => _error = 'Kamida bitta rasm tanlang');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final repo = ref.read(marketplaceRepoProvider);
    final urls = <String>[];
    for (final f in _pickedImages) {
      final bytes = await f.readAsBytes();
      final ext = f.path.split('.').last.toLowerCase();
      final url = await repo.uploadProductImage(bytes, ext);
      if (url != null) urls.add(url);
    }
    if (urls.isEmpty) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Rasmlarni yuklab boʼlmadi';
      });
      return;
    }

    final id = await repo.createProduct(
      title: title,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      price: price,
      compareAtPrice: double.tryParse(_compareAt.text.trim()),
      categoryId: _categoryId,
      condition: _condition,
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      quantity: int.tryParse(_quantity.text.trim()) ?? 1,
      isNegotiable: _isNegotiable,
      shippingAvailable: _shippingAvailable,
      shippingPrice: double.tryParse(_shippingPrice.text.trim()) ?? 0,
      imageUrls: urls,
    );

    if (!mounted) return;
    if (id != null) {
      ref.invalidate(sellerProductsProvider);
      ref.invalidate(productsProvider);
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _error = 'Mahsulotni yaratib boʼlmadi';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AlsamosColors.of(context);
    final brand = Theme.of(context).colorScheme.primary;
    final mq = MediaQuery.of(context);
    final cats = ref.watch(categoriesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(bottom: mq.padding.bottom),
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: c.border, borderRadius: BorderRadius.circular(8)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Icon(LucideIcons.packagePlus, color: brand),
              const SizedBox(width: 8),
              Text('Yangi mahsulot',
                  style: TextStyle(
                      color: c.foreground,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.x, size: 20),
              ),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                _label(c, 'Rasmlar (${_pickedImages.length}/10)'),
                const SizedBox(height: 8),
                _imageGrid(c, brand),
                const SizedBox(height: 14),
                _label(c, 'Sarlavha *'),
                const SizedBox(height: 6),
                _input(_title, hint: 'Mahsulot nomi', cap: TextCapitalization.sentences),
                const SizedBox(height: 12),
                _label(c, 'Tavsif'),
                const SizedBox(height: 6),
                _input(_description, hint: 'Mahsulot haqida...', maxLines: 4),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(c, 'Narx (USD) *'),
                        const SizedBox(height: 6),
                        _input(_price, hint: '0', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(c, 'Eski narx'),
                        const SizedBox(height: 6),
                        _input(_compareAt, hint: '0', keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(c, 'Soni'),
                        const SizedBox(height: 6),
                        _input(_quantity, keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(c, 'Yetkazish narxi'),
                        const SizedBox(height: 6),
                        _input(_shippingPrice, keyboardType: TextInputType.number),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                _label(c, 'Holati'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _conditions.map((co) {
                    final selected = _condition == co.$1;
                    return ChoiceChip(
                      label: Text(co.$2),
                      selected: selected,
                      selectedColor: brand,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : c.foreground,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      backgroundColor: c.card,
                      side: BorderSide(color: c.border.withValues(alpha: 0.4)),
                      onSelected: (_) => setState(() => _condition = co.$1),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                _label(c, 'Kategoriya'),
                const SizedBox(height: 6),
                cats.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const SizedBox(),
                  data: (list) => Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: list.map((cat) {
                      final selected = _categoryId == cat.id;
                      return ChoiceChip(
                        label: Text('${cat.icon ?? ""} ${cat.name}'.trim()),
                        selected: selected,
                        selectedColor: brand,
                        labelStyle: TextStyle(
                          color: selected ? Colors.white : c.foreground,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        backgroundColor: c.card,
                        side: BorderSide(color: c.border.withValues(alpha: 0.4)),
                        onSelected: (_) => setState(
                            () => _categoryId = selected ? null : cat.id),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
                _label(c, 'Joylashuv'),
                const SizedBox(height: 6),
                _input(_location, hint: 'Shahar'),
                const SizedBox(height: 12),
                _switchTile(c, 'Narx kelishiladi', _isNegotiable,
                    (v) => setState(() => _isNegotiable = v)),
                _switchTile(c, 'Yetkazib berish mavjud', _shippingAvailable,
                    (v) => setState(() => _shippingAvailable = v)),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(
                          color: Color(0xFFEF4444), fontSize: 13)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brand,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Eʼlon qilish',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _imageGrid(AlsamosColors c, Color brand) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _pickedImages.length < 10
          ? _pickedImages.length + 1
          : _pickedImages.length,
      itemBuilder: (_, i) {
        if (i == _pickedImages.length) {
          return InkWell(
            onTap: _pickImages,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              decoration: BoxDecoration(
                color: brand.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: brand.withValues(alpha: 0.4),
                    style: BorderStyle.solid,
                    width: 1.5),
              ),
              child: Icon(LucideIcons.imagePlus, color: brand, size: 22),
            ),
          );
        }
        final file = _pickedImages[i];
        return Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(file.path), fit: BoxFit.cover),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: () => setState(() => _pickedImages.removeAt(i)),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Color(0xCCEF4444),
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
              ),
            ),
          ),
          if (i == 0)
            Positioned(
              bottom: 2,
              left: 2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: brand,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Asosiy',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            ),
        ]);
      },
    );
  }

  Widget _label(AlsamosColors c, String t) => Text(t,
      style: TextStyle(
          color: c.foreground, fontSize: 13, fontWeight: FontWeight.w700));

  Widget _input(TextEditingController c,
      {String? hint,
      int maxLines = 1,
      TextInputType? keyboardType,
      TextCapitalization cap = TextCapitalization.none}) {
    final col = AlsamosColors.of(context);
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: cap,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: col.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: col.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 1.5)),
      ),
    );
  }

  Widget _switchTile(
      AlsamosColors c, String label, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: c.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
        Switch.adaptive(value: value, onChanged: onChanged),
      ]),
    );
  }
}
