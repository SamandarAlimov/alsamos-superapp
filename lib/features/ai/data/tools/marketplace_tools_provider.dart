// Riverpod provider for MarketplaceTools.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../marketplace/data/marketplace_repository.dart';
import 'marketplace_tools.dart';

/// Provider for marketplace tools instance.
final marketplaceToolsProvider = Provider<MarketplaceTools>((ref) {
  return const MarketplaceTools(
    repository: MarketplaceRepository(),
  );
});
