# Alsamos AI Agent kontrakti (v1.0.0)

Bu hujjat Flutter (`alsamos-superapp`) va Web (`socialalsamos`) mijozlari uchun
**bir xil** AI backend kontraktini belgilaydi. To'liq spetsifikatsiya web
reposidagi `docs/AI_PLATFORM_SPEC.md` faylida. Ikkala repo bir vaqtda
yangilanishi shart — nomutanosiblik xatolik hisoblanadi.

## 1. Backend (umumiy)

Har ikki mijoz bitta Supabase loyihasidagi edge funksiyalariga murojaat qiladi:

| Funksiya | Vazifa |
| --- | --- |
| `ai-agent` | Asosiy agent: model tanlash, tool-calling, SSE oqim |
| `code-sandbox` | Kodni izolyatsiyada ishga tushirish |
| `ai-generate-image` | Bevosita rasm generatsiyasi (legacy/yordamchi) |

## 2. So'rov formati (`POST /functions/v1/ai-agent`)

```json
{
  "messages": [{ "role": "user", "content": "..." }],
  "mode": "chat | agent",
  "model": "auto | fast | balanced | coding | reasoning | vision",
  "toolGroups": ["web", "image", "video", "code", "alsamos", "connectors", "computer"],
  "conversationId": "uuid | null",
  "contractVersion": "1.0.0"
}
```

Sarlavhalar: `Authorization: Bearer <access_token>`, `apikey: <anon key>`.

## 3. SSE hodisalari

Har bir qator `data: {json}` ko'rinishida, oxirida `data: [DONE]`.

| `type` | Maydonlar |
| --- | --- |
| `meta` | `model`, `task`, `language` |
| `delta` | `text` |
| `tool_call` | `id`, `name`, `args` |
| `tool_result` | `id`, `name`, `ok`, `summary`, `data` |
| `notice` | `message` |
| `error` | `message` |

`tool_result.data` kelishilgan kalitlari: `sources[]`, `imageUrl`,
`jobId`/`status`/`kind`, `execution{ok,logs,result,error,durationMs}`,
`taskId`/`action`/`status`/`reason`.

## 4. Vosita guruhlari

`web`, `image`, `video`, `code`, `alsamos`, `connectors`, `computer`.
Standart yoqilgan: `web`, `image`, `code`, `alsamos`.
`computer` — sezgir guruh, faqat foydalanuvchi yoqsa va har bir vazifa
alohida tasdiqlansa ishlaydi.

## 5. Kompyuterni boshqarish (Alsamos Bridge)

1. Agent `computer_task` vositasini chaqiradi → `ai_computer_tasks` jadvaliga
   `pending_approval` holatida yozuv tushadi (15 daqiqada muddati tugaydi).
2. Foydalanuvchi ilovada tasdiqlaydi → `approved`.
3. Lokal Bridge agenti navbatni o'qib bajaradi, natijani yozadi (`done`/`failed`).
4. Agent `computer_task_result` bilan natijani oladi.

Ruxsat etilgan amallar: `shell`, `read_file`, `write_file`, `list_dir`, `open`,
`screenshot`, `click`, `type_text`, `key`.

## 6. Fayl moslik jadvali (parity)

| Web (`socialalsamos`) | Flutter (`alsamos-superapp`) |
| --- | --- |
| `src/lib/ai/capabilities.ts` | `lib/features/ai/domain/ai_capabilities.dart` |
| `src/lib/ai/agentClient.ts` | `lib/features/ai/data/ai_agent_client.dart` |
| `src/components/ai/types.ts` | `lib/features/ai/domain/ai_message.dart` |
| `src/components/ai/AIToolTimeline.tsx` | AI ekranidagi tool timeline widget |
| `src/components/ai/AIModelPicker.tsx` | Model tanlash sheet |
| `src/components/ai/AIToolsMenu.tsx` | Vositalar sheet |
| `src/components/ai/AIConnectorsDialog.tsx` | Konnektorlar ekrani |

## 7. Parity tekshiruvi (PR oldidan)

- [ ] `aiContractVersion` == `AI_CONTRACT_VERSION`
- [ ] Vosita guruhlari va vosita nomlari bir xil
- [ ] Model va rejim identifikatorlari bir xil
- [ ] SSE hodisa turlari to'liq qo'llanadi
- [ ] `computer` guruhi tasdiq oqimisiz ishlamaydi
