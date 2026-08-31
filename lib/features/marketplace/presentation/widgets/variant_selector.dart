import 'package:flutter/material.dart';

import '../../data/models/product_model.dart';

/// Lets the buyer pick one [ProductVariant] of a product.
///
/// Deliberately self-contained: it takes plain data in and reports the chosen
/// variant out, so it can be dropped into any product surface without touching
/// the marketplace page. The parent owns the selection and passes
/// `variant?.id` to `MarketplaceRepository.addToCart(..., variantId: ...)`.
///
/// Option rows are derived from the `options` jsonb of the variants, so a
/// seller can invent their own axes ("Rang", "Hajm", "O'lcham") without any
/// client change.
class VariantSelector extends StatefulWidget {
  /// Active variants of the product, ideally already ordered by `position`.
  final List<ProductVariant> variants;

  /// `products.price`, used when a variant does not override the price.
  final double basePrice;

  final String currency;

  /// Fires with the resolved variant, or null while the selection is still
  /// incomplete or impossible.
  final ValueChanged<ProductVariant?> onSelected;

  const VariantSelector({
    super.key,
    required this.variants,
    required this.basePrice,
    required this.onSelected,
    this.currency = 'USD',
  });

  @override
  State<VariantSelector> createState() => _VariantSelectorState();
}

class _VariantSelectorState extends State<VariantSelector> {
  final Map<String, String> _selected = {};
  List<String> _optionNames = const [];

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(VariantSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variants != widget.variants) {
      _selected.clear();
      _prepare();
    }
  }

  void _prepare() {
    _optionNames = _collectOptionNames();

    // Preselect the first variant that can actually be bought, so the price
    // shown on open is a real price and not a placeholder.
    ProductVariant? initial;
    for (final v in widget.variants) {
      if (v.isActive && v.quantity > 0) {
        initial = v;
        break;
      }
    }
    initial ??= widget.variants.isNotEmpty ? widget.variants.first : null;

    if (initial != null && _optionNames.isNotEmpty) {
      for (final name in _optionNames) {
        final value = initial.options[name]?.toString();
        if (value != null && value.isNotEmpty) _selected[name] = value;
      }
    }

    // Never call back synchronously during build/mount.
    final resolved = _resolve();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onSelected(resolved);
    });
  }

  /// Option names in first-appearance order. Insertion order is meaningful:
  /// sellers tend to list the primary axis first.
  List<String> _collectOptionNames() {
    final names = <String>[];
    for (final v in widget.variants) {
      for (final key in v.options.keys) {
        if (key.isNotEmpty && !names.contains(key)) names.add(key);
      }
    }
    // Rows only make sense when every variant describes every axis; otherwise
    // a partially-specified catalogue would produce unresolvable selections.
    for (final v in widget.variants) {
      for (final name in names) {
        final value = v.options[name]?.toString();
        if (value == null || value.isEmpty) return const [];
      }
    }
    return names;
  }

  List<String> _valuesFor(String name) {
    final values = <String>[];
    for (final v in widget.variants) {
      final value = v.options[name]?.toString();
      if (value != null && value.isNotEmpty && !values.contains(value)) {
        values.add(value);
      }
    }
    return values;
  }

  bool _matches(ProductVariant variant, Map<String, String> selection) {
    for (final entry in selection.entries) {
      if ((variant.options[entry.key]?.toString() ?? '') != entry.value) {
        return false;
      }
    }
    return true;
  }

  ProductVariant? _variantFor(Map<String, String> selection) {
    for (final v in widget.variants) {
      if (_matches(v, selection)) return v;
    }
    return null;
  }

  ProductVariant? _resolve() {
    if (_optionNames.isEmpty) return null;
    if (_selected.length != _optionNames.length) return null;
    return _variantFor(_selected);
  }

  /// The variant a chip would lead to, keeping the other axes as they are.
  ProductVariant? _candidate(String name, String value) {
    final trial = Map<String, String>.from(_selected);
    trial[name] = value;
    return _variantFor(trial);
  }

  void _pick(String name, String value) {
    setState(() {
      _selected[name] = value;
    });
    widget.onSelected(_resolve());
  }

  void _pickFlat(ProductVariant variant) {
    setState(() {
      _selected
        ..clear()
        ..['__variant'] = variant.id;
    });
    widget.onSelected(variant);
  }

  String _money(double amount) {
    final whole = amount == amount.roundToDouble();
    final text = whole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
    return widget.currency == 'USD' ? '\$$text' : '$text ${widget.currency}';
  }

  double _priceOf(ProductVariant variant) => variant.price ?? widget.basePrice;

  @override
  Widget build(BuildContext context) {
    if (widget.variants.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final resolved = _resolve();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_optionNames.isEmpty)
          _buildFlatList(theme)
        else
          for (final name in _optionNames) _buildOptionRow(theme, name),
        if (resolved != null) _buildStockHint(theme, resolved),
        if (_optionNames.isNotEmpty && resolved == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Bu kombinatsiya mavjud emas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionRow(ThemeData theme, String name) {
    final values = _valuesFor(name);
    final chosen = _selected[name];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (chosen != null) ...[
                Text(
                  ': ',
                  style: theme.textTheme.labelLarge,
                ),
                Expanded(
                  child: Text(
                    chosen,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in values)
                _buildChip(theme, name: name, value: value),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChip(ThemeData theme, {required String name, required String value}) {
    final candidate = _candidate(name, value);
    // No matching variant at all: the combination does not exist, so the chip
    // must not be selectable.
    final exists = candidate != null && candidate.isActive;
    final soldOut = exists && candidate.quantity <= 0;
    final isSelected = _selected[name] == value;

    final Color background;
    final Color foreground;
    if (isSelected) {
      background = theme.colorScheme.primary;
      foreground = theme.colorScheme.onPrimary;
    } else if (!exists) {
      background = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
      foreground = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
    } else {
      background = theme.colorScheme.surfaceContainerHighest;
      foreground = theme.colorScheme.onSurface;
    }

    return Semantics(
      selected: isSelected,
      enabled: exists,
      button: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: exists ? () => _pick(name, value) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                decoration: soldOut ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fallback for catalogues whose variants do not share option keys: show the
  /// variants themselves, label and price, instead of rendering nothing.
  Widget _buildFlatList(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Variant',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final variant in widget.variants)
              _buildFlatChip(theme, variant),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildFlatChip(ThemeData theme, ProductVariant variant) {
    final isSelected = _selected['__variant'] == variant.id;
    final enabled = variant.isActive;
    final label = variant.label.isEmpty
        ? (variant.sku ?? 'Variant')
        : variant.label;

    return Material(
      color: isSelected
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => _pickFlat(variant) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  decoration:
                      variant.isSoldOut ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                _money(_priceOf(variant)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStockHint(ThemeData theme, ProductVariant variant) {
    if (variant.isSoldOut) {
      return Text(
        'Bu variant tugagan',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (variant.quantity < 5) {
      return Text(
        'Omborda ${variant.quantity} dona qoldi',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.tertiary,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
