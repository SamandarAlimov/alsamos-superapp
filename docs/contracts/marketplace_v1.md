# Marketplace Contract v1 (cross-client)

Canonical for both clients:

- Web: `SamandarAlimov/socialalsamos` (React, `src/components/marketplace/**`)
- Flutter: this repo (`lib/features/marketplace/**`)

Both talk to the same Supabase project. The database is the source of truth;
neither client may reimplement business rules locally.

## Rule 0: never write orders directly

`public.orders`, `public.order_items`, `public.marketplace_payments`,
`public.product_variants.quantity` and `public.products.quantity` must never be
inserted or updated from client code. Every mutation goes through an RPC.

This rule exists because the Flutter client used to `INSERT` into `orders` with
`order_number: 'TMP'`, which silently skipped stock reservation, the wallet
debit, the payment ledger and receipt generation.

## Canonical RPCs

### `process_marketplace_order(_shipping_address jsonb, _payment_method text, _notes text)`

Reads the caller's cart server-side. Does everything atomically: validates
lines, locks variant then product rows, splits one order per seller, applies
variant pricing (`coalesce(pv.price, p.price)`), charges shipping per unit,
decrements stock, debits the wallet, writes the ledger row and the receipt,
bumps seller counters and clears the cart.

Required `_shipping_address` keys: `full_name`, `phone`, `street`, `city`.
Extra keys are stored as-is, so `region`, `zip`, `latitude`, `longitude` and
`geo_label` are allowed and preserved.

`_payment_method` must be one of `wallet`, `card_on_delivery`, `cash`.

Returns:

```json
{ "success": true, "order_ids": ["uuid"], "payment_status": "paid|pending", "total": 0, "currency": "USD" }
```

Error codes (raised as exceptions, both clients map them to Uzbek copy):
`not_authenticated`, `invalid_payment_method`, `invalid_shipping_address`,
`empty_cart`, `invalid_quantity`, `product_unavailable`, `insufficient_stock`,
`insufficient_balance`.

### `marketplace_update_order_status(_order_id uuid, _status text, _reason text)`

The only way to move an order. Enforces who may act, the allowed transition,
stock restoration and wallet refunds, and writes `marketplace_order_events`.

Allowed transitions: `pending -> processing -> shipped -> delivered`, and
`cancelled` from `pending` or `processing`. A buyer may cancel only before the
order ships; advancing the chain is seller-only.

Error codes: `not_authenticated`, `invalid_status`, `order_not_found`,
`not_authorized`, `seller_only`, `cancel_window_closed`, `status_unchanged`,
`order_finalized`, `invalid_transition`.

### `increment_product_views(_product_id uuid)`

Call once per product-detail open, deduplicated per session on the client.

### `get_seller_response_stats(_seller_user_id uuid)`

Aggregate-only seller responsiveness (rate, average minutes, online, last
seen). Returns `NULL` rate/time below three buyer conversations. Never read
`messages` directly to compute this.

### `get_product_review_summary(_product_id uuid)`

Rating summary. Reviews are insertable only by a buyer who has a `delivered`
order containing that product; the rule is enforced by RLS, so both clients
must hide or disable the review form instead of relying on an error toast.

## Payment methods

| id | Status | Notes |
|---|---|---|
| `card_on_delivery` | Enabled, **default** | Works without a merchant contract. |
| `cash` | Enabled | Settled on delivery. |
| `wallet` | Enabled | Debited inside the checkout RPC. No real top-up rail exists yet. |
| `payme`, `click`, `uzum` | Disabled | Require YaTT/MCHJ plus a merchant contract. |

The web client owns the provider registry in `src/lib/payments/`. Flutter must
mirror the same ids and the same enabled set; it must not offer a method the
registry marks disabled.

## Variants

`cart_items.product_variant_id` and `order_items.product_variant_id` +
`variant_options` are part of the contract. Price and stock come from the
variant when one is selected, otherwise from the product. A client that ignores
variants will show the wrong price, so Flutter must carry the variant id
through cart and checkout.

## Migrations

One database, two repos. Keep marketplace migrations in the web repo
(`socialalsamos/supabase/migrations/`) and reference them here instead of
duplicating SQL, so migration order stays linear. Do not add a second copy of
`process_marketplace_order` in this repo.

## Known gaps (do not treat as done)

- No PSP edge function exists for Payme/Click/Uzum.
- No wallet top-up flow; balance is funded manually.
- Delivery coordinates are captured on web but not yet stored in
  `shipping_address`.
- Flutter still links video commerce by "products of the video author" instead
  of the real `marketplace_video_products` table.
