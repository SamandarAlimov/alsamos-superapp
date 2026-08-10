# Payment Webhook Handler

Handles payment gateway callbacks from Click, Payme, Uzcard, and card payment providers.

## Security Architecture

**CRITICAL:** All payment SECRET KEYS live server-side only. The Flutter client contains only PUBLIC identifiers.

### Server-Side Secrets (Supabase Edge Function)

Configure via Supabase CLI:

```bash
supabase secrets set \
  CLICK_SECRET_KEY=your_click_secret_key \
  PAYME_KEY=your_payme_secret_key \
  --project-ref mbhjganbihamoiqmankv
```

These secrets are used for webhook signature verification and are never exposed to clients.

### Client-Side Public IDs (Flutter App)

Build the Flutter app with public identifiers only:

```bash
flutter build windows \
  --dart-define=CLICK_SERVICE_ID=12345 \
  --dart-define=CLICK_MERCHANT_ID=67890 \
  --dart-define=PAYME_MERCHANT_ID=abcdef1234567890
```

These are safe to ship in the app binary.

## Webhook Signature Verification

### Click (Uzbekistan)

**Prepare (action=0):**
```
sign = MD5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id + amount + action + sign_time)
```

**Complete (action=1):**
```
sign = MD5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id + merchant_prepare_id + amount + action + sign_time)
```

Returns error `-1` (SIGN CHECK FAILED) if signature invalid.

### Payme (Paycom)

Uses HTTP Basic Authentication:
```
Authorization: Basic base64("Paycom:" + PAYME_KEY)
```

Returns JSON-RPC error `-32504` (insufficient privileges) if auth fails.

### Uzcard & Card

Signature verification stubs in place. Implement when credentials available.

## Deployment

```bash
supabase functions deploy payment-webhook --project-ref mbhjganbihamoiqmankv
```

## Testing

Test webhook locally:

```bash
supabase functions serve payment-webhook

# Test Click webhook
curl -X POST http://localhost:54321/functions/v1/payment-webhook \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "click",
    "orderId": "...",
    "transactionId": "...",
    "amount": 100000,
    "status": "completed",
    "signature": "...",
    "metadata": {
      "click_trans_id": "...",
      "service_id": "...",
      "merchant_trans_id": "...",
      "amount": 100000,
      "action": 1,
      "sign_time": "2024-01-01 12:00:00"
    }
  }'
```

## Environment Variables

| Variable | Type | Description |
|----------|------|-------------|
| `CLICK_SECRET_KEY` | Secret | Click signature verification key (server) |
| `PAYME_KEY` | Secret | Payme authentication key (server) |
| `CLICK_SERVICE_ID` | Public | Click service ID (client via --dart-define) |
| `CLICK_MERCHANT_ID` | Public | Click merchant ID (client via --dart-define) |
| `PAYME_MERCHANT_ID` | Public | Payme merchant ID (client via --dart-define) |
