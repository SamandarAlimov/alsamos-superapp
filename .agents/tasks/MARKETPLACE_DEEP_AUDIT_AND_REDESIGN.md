# Marketplace Deep Audit & Professional Redesign

**Status**: Investigation Phase  
**Priority**: High  
**Scope**: Marketplace module comprehensive defect fixes + cross-module integration  
**Created**: 2026-08-10  

---

## Executive Summary

This document provides a comprehensive root-cause analysis of confirmed defects in the Alsamos Marketplace module and outlines the integration architecture required to elevate it from an isolated feature to a deeply integrated e-commerce module on par with best-in-class marketplace products.

**Key Findings**:
1. **Grid pagination is NOT broken at the data layer** — the repository correctly fetches up to 60 products with proper filtering
2. **The real issue is a RESPONSIVE GRID LAYOUT BUG** — fixed column counts don't adapt to available width
3. **Seller dashboard stat cards have a LAYOUT/CONSTRAINT DEFECT** — content isn't filling card height properly
4. **Charts work correctly** when data exists; empty states need proper zero-data UI treatment
5. **Several interactive controls are wired but need UX improvements** (optimistic UI, visual feedback)
6. **Cross-module integration is entirely missing** — no AI, Payment, or Map integration exists

---

## PART 1: ROOT-CAUSE DIAGNOSIS

### Issue A: Product Grid Shows Few Items with Large Empty Space

#### Investigation Results

**Diagnosis**: This is **NOT a pagination bug**. The data layer is correct.

```dart
// lib/features/marketplace/data/marketplace_repository.dart:43-51
Future<List<Product>> fetchProducts({
  String? categorySlug,
  String? search,
  int limit = 50,  // ← Fetches up to 50 products (configurable)
}) async {
  // ... proper query construction with filters
  final data = await q.order('created_at', ascending: false).limit(limit);
  // ... returns full list with liked status
}
```

**The real culprit is in `marketplace_page.dart:382-393`**:

```dart
Widget _productGrid(List<Product> list) {
  final width = MediaQuery.sizeOf(context).width;
  final columns = width >= 1200
      ? 4
      : width >= Responsive.desktopMin
          ? 3
          : width < 360
              ? 1
              : 2;  // ← Column count logic
  return GridView.builder(
    // ...
    crossAxisCount: columns,  // ← Fixed column count
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
    childAspectRatio: columns == 1 ? 1.35 : 0.6,  // ← Fixed aspect ratio
    // ...
  );
}
```

**Root Cause**:
- The column count breakpoints are too conservative (2 columns on mobile, 3 on tablet, 4 on wide desktop)
- The `childAspectRatio: 0.6` creates very tall cards that don't efficiently use vertical space
- On wide screens, 4 columns leaves large gutters/margins unused
- The grid doesn't reflow to fill available width — cards cluster to one side

**Evidence from Current Code**:
- `productsProvider` in `marketplace_provider.dart:83-106` correctly filters and sorts, returning full lists
- Fallback demo data (`_demoProducts()`) returns 12 items, so empty data isn't the issue
- The `itemCount: list.length` correctly renders all fetched products
- Screenshots show cards left-aligned with empty right-side space = layout issue, not data issue

#### Solution

**Not a query fix — a responsive grid redesign**:

1. **Dynamic column calculation** based on available width and optimal card width (not fixed breakpoints):
   ```dart
   final availableWidth = MediaQuery.sizeOf(context).width - 32; // minus padding
   const minCardWidth = 160.0;  // minimum readable card
   const maxCardWidth = 240.0;  // maximum before cards look stretched
   const idealCardWidth = 200.0;
   
   final columns = max(1, (availableWidth / idealCardWidth).floor());
   final cardWidth = availableWidth / columns - (10 * (columns - 1) / columns); // account for gaps
   ```

2. **Make aspect ratio responsive** to card width for consistent visual weight
3. **Add proper pagination/infinite scroll**:
   - Current code fetches `limit: 60` all at once (line 92 in `marketplace_provider.dart`)
   - Need to fetch in pages (e.g., 20 per page) and append on scroll
   - Add `ScrollController` to detect near-bottom and trigger next page load

---

### Issue B: Grid Does Not Reflow/Fill Available Width Responsively

**Status**: ✅ Confirmed — Same root cause as Issue A

The fixed `crossAxisCount` and breakpoint-based column logic doesn't adapt fluidly to available width. See Issue A solution.

---

### Issue C: Seller Dashboard Stat Cards Broken/Empty

#### Investigation Results

**File**: `lib/features/marketplace/presentation/widgets/seller_dashboard.dart:110-149`

```dart
Widget _kpi(AlsamosColors c, Color brand, IconData icon, String label,
    String value, Color accent) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: c.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: c.border.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,  // ← Spreads content
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accent, size: 16),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, /* ... */),
            const SizedBox(height: 2),
            Text(value, /* fontSize: 20, fontWeight: w800 ... */),
          ],
        ),
      ],
    ),
  );
}
```

**Root Cause**: 
- The parent `GridView.count` (line 92) has `childAspectRatio: 1.5`, creating ~150px tall cards
- The `Column` with `MainAxisAlignment.spaceBetween` tries to spread the icon (top) and text (bottom)
- Because the inner text `Column` is not wrapped in `Expanded`, it doesn't take available space
- Result: Icon at top, large gap, text crammed at bottom

**Evidence**: 
- Chart cards (lines 166-195) use proper structure with `SizedBox(height: height, child: child)` — charts render correctly
- The issue is specific to stat cards' vertical layout distribution

#### Solution

Replace `MainAxisAlignment.spaceBetween` with natural flow + proper padding:

```dart
child: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: accent, size: 16),
    ),
    const Spacer(),  // ← Push content down naturally
    Text(label, /* ... */),
    const SizedBox(height: 2),
    Text(value, /* fontSize: 20, fontWeight: w800 ... */),
  ],
),
```

Or redesign cards to be more compact and information-dense (single-line icon + label + value).

---

### Issue D: Icons Look Like Emoji, Not Professional Iconography

#### Investigation Results

**Current state**:
- Seller dashboard uses `lucide_flutter` icons (✅ professional)
- Category chips use emoji strings (`'📱'`, `'👟'`, `'🏠'`, etc.) — see `marketplace_page.dart:294`, `marketplace_provider.dart:42-49`
- Product cards use `lucide_flutter` icons (✅ professional)

**Root Cause**:
- Category icons stored as emoji in fallback data
- Backend `product_categories` table likely has emoji in `icon` column
- This is a **data + UI decision**, not purely a UI bug

#### Solution

1. **Short-term**: Replace emoji in fallback data with `IconData` references or Material Icons font codes
2. **Long-term**: Migrate category icons to Lucide icon names in the database
3. **UI layer**: Map category icon string to `IconData` widget instead of raw `Text(icon)`

---

### Issue E: Sort Modal Positioned Incorrectly

#### Investigation Results

**File**: `marketplace_page.dart:520-567`

```dart
void _openFilters() {
  final c = AlsamosColors.of(context);
  final brand = Theme.of(context).colorScheme.primary;
  showModalBottomSheet(
    context: context,
    backgroundColor: c.background,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) {
      // ... ChoiceChip selection UI
    },
  );
}
```

**Diagnosis**: The code uses `showModalBottomSheet`, which is **correct for mobile**.

**Root Cause of User-Reported Issue**:
- On **desktop/wide layouts**, `showModalBottomSheet` still renders as a full-width bottom sheet (correct mobile pattern)
- User expects a **popover/dropdown anchored to the filter button** on desktop (matching typical desktop UX)
- Current implementation doesn't differentiate between mobile and desktop contexts

#### Solution

**Responsive modal pattern**:

```dart
void _openFilters() {
  if (context.responsive.isDesktop) {
    // Desktop: Show anchored popover
    _showFilterPopover(context);
  } else {
    // Mobile: Show bottom sheet
    showModalBottomSheet(/* existing code */);
  }
}
```

Use a package like `positioned_tap_detector_2` or build custom `Stack`+`Positioned` logic to anchor popover to button.

---

### Issue F: Several Buttons Non-Functional

#### Functional Audit Table

| Control | Currently Wired? | Expected Behavior | Status |
|---------|-----------------|-------------------|--------|
| Filter/adjustment icon button | ✅ Yes | Opens sort bottom sheet | ✅ Working (line 238) |
| Category chips (Barchasi, Electronics, etc.) | ✅ Yes | Filters product grid by category | ✅ Working (lines 279-289) |
| Heart/save icon on product cards | ✅ Yes | Toggles saved state, updates UI | ✅ Working (product_card.dart:66-77) with optimistic UI |
| "Qo'shish" (Add) button on seller card | ✅ Yes | Opens create product sheet | ✅ Working (seller_dashboard.dart:57-60) |
| Time-range toggle (7/30/90 days) | ✅ Yes | Re-queries dashboard stats | ✅ Working (seller_dashboard.dart:80-87) |
| Cart quantity +/- steppers | ✅ Yes | Updates quantity, recalculates total | ✅ Working (cart_sheet.dart:161-169) |
| Trash icon in cart | ✅ Yes | Removes item from cart | ✅ Working (cart_sheet.dart:174-177) |
| "Buyurtma berish" (Place Order) button | ✅ Yes | Opens checkout sheet | ✅ Working (cart_sheet.dart:103-107) |
| Sort "Qo'llash" (Apply) button | ✅ Yes | Closes sheet (filter already applied via ChoiceChip.onSelected) | ✅ Working (line 561) |

**Conclusion**: All controls are functionally wired. User perception of "not working" may be due to:
1. **Lack of visual feedback** (loading spinners, success toasts, optimistic UI)
2. **Slow backend responses** making actions feel unresponsive
3. **Missing empty state** messaging when filter results return zero items

**Recommended Fixes**:
- Add loading state indicators on filter/category changes
- Add success/error toast notifications on like/cart actions
- Improve empty state messaging: "No products found for 'Electronics'" vs. generic "Mahsulot topilmadi"

---

## PART 2: CROSS-MODULE INTEGRATION ARCHITECTURE

### Current State: Marketplace is an Island

**No integrations exist**:
- ❌ No "Send to AI" action on products
- ❌ AI Assistant cannot query marketplace products
- ❌ AI Assistant cannot search/order products conversationally
- ❌ Cart checkout doesn't route through Payment module
- ❌ No "View on map" for seller locations
- ❌ No proximity filtering for local listings

### Integration 7.1: Marketplace → AI Assistant

**Requirement**: Add "AI ga yuborish" action to product cards

**Implementation Plan**:

1. **Add action to product detail sheet** (`product_detail.dart`):
   ```dart
   IconButton(
     icon: const Icon(LucideIcons.messageSquare),
     onPressed: () => _sendToAI(context, product),
   )
   ```

2. **Create shared context payload**:
   ```dart
   // lib/core/models/ai_context.dart
   class AIProductContext {
     final String productId;
     final String title;
     final double price;
     final String? sellerName;
     final String? description;
     final List<String> imageUrls;
     // ... toJson()
   }
   ```

3. **Navigate to AI page with context**:
   ```dart
   void _sendToAI(BuildContext context, Product product) {
     final ctx = AIProductContext.fromProduct(product);
     Navigator.pushNamed(
       context,
       '/ai',
       arguments: AIPageArgs(
         initialContext: ctx,
         initialPrompt: 'Tell me about this product',
       ),
     );
   }
   ```

4. **AI page must render product as rich card** (not just text) — similar to how AI can render images/files

**Files to modify**:
- `lib/features/marketplace/presentation/widgets/product_detail.dart` (add button)
- `lib/features/ai/presentation/pages/ai_page.dart` (accept product context)
- `lib/features/ai/presentation/widgets/ai_context_card.dart` (NEW: render product)

---

### Integration 7.2: AI Assistant → Marketplace (Product Q&A)

**Requirement**: AI can answer questions about specific products using real data

**Implementation Plan**:

1. **Create AI tool/function**: `get_product_details(product_id: string)`
   ```dart
   // lib/features/ai/data/tools/marketplace_tools.dart
   Future<Map<String, dynamic>> getProductDetails(String productId) async {
     final repo = MarketplaceRepository();
     final product = await repo.fetchProductById(productId);
     if (product == null) return {'error': 'Product not found'};
     return {
       'title': product.title,
       'price': product.price,
       'seller': product.seller?.businessName,
       'inStock': product.quantity > 0,
       'description': product.description,
       // ...
     };
   }
   ```

2. **Register tool with AI backend** (Bedrock/Claude function-calling):
   ```json
   {
     "name": "get_product_details",
     "description": "Fetch current details of a marketplace product by ID",
     "parameters": {
       "product_id": {
         "type": "string",
         "description": "The unique product identifier"
       }
     }
   }
   ```

3. **AI service must call tool when user asks about a product**

**Files to create/modify**:
- `lib/features/ai/data/tools/marketplace_tools.dart` (NEW)
- `lib/features/ai/data/ai_service.dart` (register tool)

---

### Integration 7.3: AI Assistant → Marketplace Search & Ordering

**Requirement**: Conversational marketplace search and checkout

**Implementation Plan**:

1. **Create search tool**: `search_marketplace(query: string, category?: string, max_price?: number)`
   ```dart
   Future<List<Map<String, dynamic>>> searchMarketplace({
     required String query,
     String? category,
     double? maxPrice,
   }) async {
     final repo = MarketplaceRepository();
     final products = await repo.fetchProducts(
       search: query,
       categorySlug: category,
       limit: 10,
     );
     return products
         .where((p) => maxPrice == null || p.price <= maxPrice)
         .map((p) => {
               'id': p.id,
               'title': p.title,
               'price': p.price,
               'seller': p.seller?.businessName,
               'image_url': p.images.firstOrNull,
             })
         .toList();
   }
   ```

2. **AI renders search results as product cards in chat** (reuse `ProductCard` widget)

3. **Create add-to-cart tool**: `add_to_cart(product_id: string, quantity: int)`
   ```dart
   Future<Map<String, dynamic>> addToCart(String productId, int quantity) async {
     final repo = MarketplaceRepository();
     final success = await repo.addToCart(productId, quantity: quantity);
     if (!success) return {'error': 'Failed to add to cart'};
     
     final cart = await repo.fetchCart();
     final total = cart.fold<double>(0, (sum, item) => 
         sum + (item.product?.price ?? 0) * item.quantity);
     
     return {
       'success': true,
       'cart_item_count': cart.length,
       'cart_total': total,
       'message': 'Added to cart. Ready to checkout?',
     };
   }
   ```

4. **Create checkout confirmation flow**:
   - AI must never silently place orders
   - AI returns: "I've added [Product] to your cart (total: $X). Would you like to proceed to checkout?"
   - User confirms → AI calls `initiate_checkout()` → navigates to checkout sheet

**Files to create/modify**:
- `lib/features/ai/data/tools/marketplace_tools.dart` (add search & cart tools)
- `lib/features/ai/presentation/widgets/ai_product_result_card.dart` (NEW: render products in chat)

---

### Integration 7.4: Marketplace ↔ Payment Module

**Requirement**: Checkout routes through existing Payment module

**Investigation** (need to read payment module code):
- What payment methods does `payment_page.dart` support?
- Does `payment_repository.dart` have a `createPaymentIntent(amount, metadata)` method?
- How does payment confirm/callback work?

**Implementation Plan** (pending investigation):

1. **Cart checkout button calls Payment module**:
   ```dart
   Future<void> _checkout(BuildContext context, List<CartItem> items) async {
     final total = items.fold<double>(0, (s, i) => 
         s + (i.product?.price ?? 0) * i.quantity);
     
     // Navigate to payment page with order metadata
     final paymentResult = await Navigator.pushNamed(
       context,
       '/payment',
       arguments: PaymentArgs(
         amount: total,
         currency: 'USD',
         metadata: {
           'order_type': 'marketplace',
           'cart_items': items.map((i) => i.toJson()).toList(),
         },
       ),
     );
     
     if (paymentResult == PaymentStatus.success) {
       // Create order records, clear cart
       await _placeOrder(items);
     }
   }
   ```

2. **After payment success, create order**:
   - Call `MarketplaceRepository.placeOrder()`
   - Split cart by seller (one order per seller)
   - Clear cart
   - Navigate to order confirmation screen

3. **Orders must appear in**:
   - Buyer's "Buyurtmalar" tab
   - Seller's dashboard

**Files to read**:
- `lib/features/payment/presentation/pages/payment_page.dart`
- `lib/features/payment/data/payment_repository.dart`

**Files to modify**:
- `lib/features/marketplace/presentation/widgets/checkout_sheet.dart`

---

### Integration 7.5: Marketplace ↔ Map Module

**Requirement**: View seller locations on map, filter by proximity

**Implementation Plan**:

1. **Add "View on map" button** to product detail sheet:
   ```dart
   if (product.seller?.location != null)
     TextButton.icon(
       icon: const Icon(LucideIcons.mapPin),
       label: const Text('Xaritada koʼrish'),
       onPressed: () => _viewOnMap(product.seller!),
     )
   ```

2. **Navigate to map with seller location**:
   ```dart
   void _viewOnMap(Seller seller) {
     // Assuming seller.location is "lat,lng" or address string
     Navigator.pushNamed(
       context,
       '/map',
       arguments: MapArgs(
         centerLat: seller.latitude,
         centerLng: seller.longitude,
         markers: [
           MapMarker(
             id: seller.id,
             lat: seller.latitude,
             lng: seller.longitude,
             title: seller.businessName,
             type: 'marketplace_seller',
           ),
         ],
       ),
     );
   }
   ```

3. **Add proximity filter** to marketplace browse tab:
   - Add "Near me" filter chip
   - Request user location permission
   - Filter products where `seller.location` is within N km of user
   - Use PostGIS or Supabase `.rpc('nearby_sellers', {user_lat, user_lng, radius_km})` for efficient geo queries

**Files to read**:
- `lib/features/map/presentation/pages/map_page.dart`
- `lib/features/map/presentation/providers/map_provider.dart`

**Files to modify**:
- `lib/features/marketplace/presentation/widgets/product_detail.dart` (add map button)
- `lib/features/marketplace/presentation/pages/marketplace_page.dart` (add "Near me" filter)
- `lib/features/marketplace/data/marketplace_repository.dart` (add proximity query)

---

## PART 3: DELIVERABLES & IMPLEMENTATION ORDER

### Phase 1: Core Defect Fixes (Estimated: 2-3 hours)

1. ✅ **Responsive grid layout** (Issue A/B)
   - Dynamic column calculation
   - Fluid card sizing
   - Maintain consistent aspect ratio

2. ✅ **Seller dashboard stat cards** (Issue C)
   - Fix layout constraint bug
   - Ensure content fills card height naturally

3. ✅ **Empty state improvements**
   - Zero-revenue/orders charts: proper "no data yet" UI
   - Sparse product grids: "Browse more" CTA cards
   - Filtered zero results: contextual "No products in [category]" messages

4. ✅ **Iconography cleanup** (Issue D)
   - Replace emoji category icons with Lucide icons
   - Consistent icon library across all marketplace widgets

5. ✅ **Modal positioning fix** (Issue E)
   - Desktop: anchored popover
   - Mobile: bottom sheet (existing)

6. ✅ **UX polish for buttons** (Issue F)
   - Add loading states
   - Add success/error toasts
   - Improve visual feedback

### Phase 2: Pagination & Performance (Estimated: 2 hours)

7. ✅ **Infinite scroll pagination**
   - Fetch 20 products per page
   - Load next page before user hits bottom
   - Show loading indicator at grid trailing edge

8. ✅ **Optimistic UI for all mutations**
   - Like/unlike
   - Add to cart
   - Remove from cart
   - Quantity changes

### Phase 3: Cross-Module Integration (Estimated: 6-8 hours)

9. ✅ **Marketplace → AI** (Integration 7.1)
   - "Send to AI" button on products
   - Product context card in AI chat

10. ✅ **AI → Marketplace Q&A** (Integration 7.2)
    - `get_product_details` tool
    - Register with AI service

11. ✅ **AI → Marketplace search & ordering** (Integration 7.3)
    - `search_marketplace` tool
    - `add_to_cart` tool
    - Product result cards in AI chat
    - Confirmation flow for checkout

12. ✅ **Marketplace → Payment** (Integration 7.4)
    - Route checkout through Payment module
    - Handle payment callbacks
    - Create orders post-payment

13. ✅ **Marketplace ↔ Map** (Integration 7.5)
    - "View on map" for seller locations
    - "Near me" proximity filter

### Phase 4: Verification (Estimated: 2 hours)

14. ✅ Run `dart analyze` — zero warnings
15. ✅ Build Android APK — confirm no regressions
16. ✅ Build Windows desktop — confirm responsive grid works on wide screens
17. ✅ Manual UI testing on mobile emulator + desktop
18. ✅ Commit with descriptive message following repo conventions

---

## PART 4: FILES TO CREATE/MODIFY

### Files to Modify

| File | Changes |
|------|---------|
| `lib/features/marketplace/presentation/pages/marketplace_page.dart` | Responsive grid, filter popover, empty states |
| `lib/features/marketplace/presentation/providers/marketplace_provider.dart` | Pagination state management |
| `lib/features/marketplace/data/marketplace_repository.dart` | Pagination queries, proximity filter |
| `lib/features/marketplace/presentation/widgets/seller_dashboard.dart` | Stat card layout fix, chart empty states |
| `lib/features/marketplace/presentation/widgets/product_card.dart` | Icon cleanup |
| `lib/features/marketplace/presentation/widgets/product_detail.dart` | "Send to AI", "View on map" buttons |
| `lib/features/marketplace/presentation/widgets/checkout_sheet.dart` | Payment module integration |

### Files to Create

| File | Purpose |
|------|---------|
| `lib/core/models/ai_context.dart` | Shared context models for cross-module communication |
| `lib/features/ai/data/tools/marketplace_tools.dart` | AI function-calling tools for marketplace |
| `lib/features/ai/presentation/widgets/ai_product_result_card.dart` | Product cards in AI chat |
| `lib/features/ai/presentation/widgets/ai_context_card.dart` | Generic context card renderer (product, order, etc.) |

---

## PART 5: RISK ASSESSMENT & MITIGATION

### Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Responsive grid breaks existing layouts | High | Low | Test on mobile, tablet, desktop before commit |
| Payment integration requires new backend endpoints | High | Medium | Check existing payment API first; stub if needed |
| AI tool registration breaks existing AI flows | Medium | Low | Test AI page independently; add feature flag |
| Map location data is missing/inconsistent | Medium | High | Add null checks; hide map features if location unavailable |
| Performance degrades with infinite scroll | Medium | Low | Profile with Flutter DevTools; add pagination threshold |

### Breaking Change Checklist

- ❌ Does NOT remove public APIs
- ❌ Does NOT change database schema (read-only changes)
- ❌ Does NOT break existing marketplace browsing flow
- ✅ Adds new optional features (integrations can be disabled if buggy)
- ✅ Maintains backward compatibility with existing product cards, cart, orders

---

## PART 6: SUCCESS CRITERIA

### Functional Criteria

- [ ] Product grid displays all available products, reflowing to fill screen width at all breakpoints
- [ ] Infinite scroll loads next page smoothly without janky scrolling
- [ ] Seller dashboard stat cards render correctly with proper content distribution
- [ ] Charts display real data when available, show proper zero-state when empty
- [ ] Category icons use professional iconography (Lucide), not emoji
- [ ] Filter modal appears as popover on desktop, bottom sheet on mobile
- [ ] All interactive controls provide immediate visual feedback (loading, success, error)
- [ ] "Send to AI" on products opens AI chat with product context card
- [ ] AI Assistant can answer "what's the price of product X?" using real data
- [ ] AI Assistant can search marketplace ("find me laptops under $1500") and render results as cards
- [ ] AI Assistant can add to cart ("order the MacBook Pro") with confirmation flow
- [ ] Cart checkout navigates to Payment module, creates orders post-payment
- [ ] "View on map" opens Map module centered on seller location
- [ ] "Near me" filter shows products from nearby sellers

### Non-Functional Criteria

- [ ] `dart analyze` passes with zero warnings
- [ ] `flutter build apk --debug` succeeds
- [ ] `flutter build windows --debug` succeeds
- [ ] UI feels responsive on 60fps scroll
- [ ] No console errors or exceptions during normal flows
- [ ] Follows existing Alsamos design system (colors, spacing, typography)

---

## NEXT STEPS

1. **Lead agent** reviews this audit and approves scope
2. **Implementation agent** executes Phase 1-2 (core fixes + pagination) — estimated 4-5 hours
3. **Code review** + verification build
4. **Integration agent** executes Phase 3 (cross-module integrations) — estimated 6-8 hours
5. **Final verification** + commit

---

## NOTES

- This is a **substantial scope** — ~12-15 hours of focused work
- Some integration work (especially Payment and AI function-calling) may require backend changes outside Flutter codebase
- If backend endpoints are missing, we can stub them and document requirements for backend team
- All changes follow existing repo conventions (Riverpod providers, repository pattern, UI component structure)
- Fragile files (`posts_repository.dart`, `messages_repository.dart`, etc.) are NOT touched by this work

---

**Document Version**: 1.0  
**Last Updated**: 2026-08-10  
**Owner**: Kiro AI Agent  
**Status**: Ready for Review & Approval
