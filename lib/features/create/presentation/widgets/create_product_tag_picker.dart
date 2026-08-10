import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/models/create_product_tag.dart';

typedef CreateProductTagSearch = Future<List<CreateProductTag>> Function(
  String query,
);

typedef CreateProductTagError = void Function(Object error);

Future<CreateProductTag?> showCreateProductTagPicker({
  required BuildContext context,
  required CreateProductTagSearch onSearch,
  CreateProductTagError? onError,
}) {
  return showModalBottomSheet<CreateProductTag>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CreateProductTagPickerSheet(
      onSearch: onSearch,
      onError: onError,
    ),
  );
}

class CreateSelectedProductTagsSection extends StatelessWidget {
  const CreateSelectedProductTagsSection({
    super.key,
    required this.products,
    required this.onAdd,
    required this.onRemove,
  });

  final List<CreateProductTag> products;
  final VoidCallback onAdd;
  final ValueChanged<CreateProductTag> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.shoppingBag,
                size: 18,
                color: colors.mutedForeground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Mahsulotlar',
                  style: TextStyle(
                    color: colors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(LucideIcons.plus, size: 15),
                label: const Text('Tag qilish'),
              ),
            ],
          ),
          if (products.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: products
                  .map(
                    (product) => InputChip(
                      avatar: _ProductThumb(
                        product: product,
                        size: 22,
                        borderRadius: 6,
                        iconSize: 14,
                      ),
                      label: Text(
                        product.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onDeleted: () => onRemove(product),
                      deleteIcon: const Icon(LucideIcons.x, size: 13),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateProductTagPickerSheet extends StatefulWidget {
  const _CreateProductTagPickerSheet({
    required this.onSearch,
    this.onError,
  });

  final CreateProductTagSearch onSearch;
  final CreateProductTagError? onError;

  @override
  State<_CreateProductTagPickerSheet> createState() =>
      _CreateProductTagPickerSheetState();
}

class _CreateProductTagPickerSheetState
    extends State<_CreateProductTagPickerSheet> {
  final _searchController = TextEditingController();
  var _loading = false;
  var _results = <CreateProductTag>[];
  var _requestId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(''));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final requestId = ++_requestId;
    final q = query.trim();
    setState(() => _loading = true);
    try {
      final products = await widget.onSearch(q);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = products;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _loading = false);
      widget.onError?.call(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.shoppingBag,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mahsulot tag qilish',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                hintText: 'Mahsulot nomi...',
                filled: true,
                fillColor: colors.muted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: colors.border),
                  itemBuilder: (context, index) {
                    final product = _results[index];
                    return Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _ProductThumb(product: product),
                        title: Text(
                          product.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${product.price.toStringAsFixed(2)} ${product.currency}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(LucideIcons.plus, size: 18),
                        onTap: () => Navigator.pop(context, product),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({
    required this.product,
    this.size = 42,
    this.borderRadius = 10,
    this.iconSize = 18,
  });

  final CreateProductTag product;
  final double size;
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = AlsamosColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: colors.muted,
          child: product.imageUrl == null
              ? Icon(
                  LucideIcons.package,
                  color: colors.mutedForeground,
                  size: iconSize,
                )
              : Image.network(product.imageUrl!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
