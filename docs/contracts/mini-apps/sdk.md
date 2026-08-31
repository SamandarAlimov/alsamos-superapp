# Mini App SDK protokoli

Bu fayl `socialalsamos/docs/contracts/mini-apps/sdk.md` bilan bir xil nusxada saqlanadi.

Mini app Alsamos ichida iframe (web) yoki WebView (mobil) sifatida ochiladi.
Aloqa `postMessage` orqali, so'rov/javob juftligi bilan boradi.

## So'rov formati (mini app -> host)

```json
{
  "source": "alsamos-mini-app",
  "id": "unikal-id",
  "method": "getInitData",
  "params": {}
}
```

## Javob formati (host -> mini app)

```json
{
  "source": "alsamos-host",
  "id": "unikal-id",
  "result": { },
  "error": null
}
```

## Metodlar

| Metod | Ruxsat | Natija |
| --- | --- | --- |
| `ready` | — | `{ sdkVersion, platform, permissions, theme }` |
| `getInitData` | `profile` | imzolangan `initData` |
| `close` | — | `{ closed: true }` |
| `openLink` | — | `{ opened: true }` |
| `share` | — | `{ shared: true }` |
| `requestPayment` | `payments` | `{ paymentId, status: "pending" }` |

## initData imzosi

```
secretKey = HMAC_SHA256(key: "WebAppData", message: MINI_APP_SDK_SECRET)
hash      = HMAC_SHA256(key: secretKey,    message: dataCheckString)
```

`dataCheckString` — `hash` dan tashqari barcha kalitlar alifbo tartibida,
`kalit=qiymat` ko'rinishida, `\n` bilan birlashtiriladi.

Tekshirish: `POST /functions/v1/mini-app-init-data?verify=1` -> `{ ok, appId, userId }`.

Qoidalar:

- `exp` muddati 1 soat; muddati o'tgani rad etiladi.
- Har bir `nonce` bir marta ishlatiladi (replay himoyasi).
- `user` obyektida faqat `id`, `username`, `name`, `photo_url`.
  **Email va telefon hech qachon uzatilmaydi.**
- Host foydalanuvchi JWT tokenini mini app'ga bermaydi.

## Flutter tomoni

WebView'da `JavaScriptChannel` orqali xuddi shu metodlar taqdim etiladi;
xabar formati va imzo qoidalari o'zgarmaydi.
