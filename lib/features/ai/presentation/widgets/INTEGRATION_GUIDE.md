# AI Composer V2 Integration Guide

## Overview
The new `AIComposerV2` widget replaces the old composer with:
- ✅ Unified input (no Chat/Imagine toggle)
- ✅ Auto-growing multiline text field
- ✅ Intent detection with visual hints
- ✅ Attachment support
- ✅ Voice button placeholder
- ✅ Send/stop button morphing
- ✅ Model selector

## Integration Steps

### 1. Import the new composer

```dart
import 'package:alsamos/features/ai/presentation/widgets/ai_composer_v2.dart';
import 'package:alsamos/features/ai/data/intent_detector.dart';
```

### 2. Replace the old `_composer()` method

**OLD CODE (remove this):**
```dart
Widget _composer(AlsamosColors c, AiState state) {
  final imagine = state.mode == 'imagine';
  final busy = state.isLoading || state.isGeneratingImage;
  // ... old implementation with Chat/Imagine toggle
}
```

**NEW CODE:**
```dart
Widget _composer(AlsamosColors c, AiState state) {
  return AIComposerV2(
    controller: _input,
    focusNode: _focus,
    onSend: _send,
    onAttach: _showAttachmentPicker,  // implement this
    onVoice: _startVoiceInput,        // implement this
    isGenerating: state.isLoading || state.isGeneratingImage,
    attachments: const [],            // TODO: wire to state
    onRemoveAttachment: (index) {     // TODO: implement
      // remove attachment at index
    },
    selectedModel: 'Gemini 3 Flash',
    onModelSelect: _showModelPicker,  // implement this
  );
}
```

### 3. Update the `_send()` method to use intent detection

**OLD CODE:**
```dart
void _send() {
  final text = _input.text.trim();
  if (text.isEmpty) return;
  final mode = ref.read(aiProvider).mode;  // ← NO MORE MODE!
  _input.clear();
  setState(() {});
  HapticFeedback.lightImpact();
  if (mode == 'imagine') {
    ref.read(aiProvider.notifier).generateImage(text);
  } else {
    ref.read(aiProvider.notifier).sendMessage(text);
  }
  // ...
}
```

**NEW CODE:**
```dart
void _send() {
  final text = _input.text.trim();
  if (text.isEmpty) return;
  
  // Detect intent
  final intent = IntentDetector.detect(text);
  
  _input.clear();
  setState(() {});
  HapticFeedback.lightImpact();
  
  // Route based on intent
  switch (intent.type) {
    case IntentType.imageGen:
      ref.read(aiProvider.notifier).generateImage(text);
      break;
    case IntentType.videoGen:
      // TODO: implement video generation
      ref.read(aiProvider.notifier).sendMessage(text);
      break;
    case IntentType.codeExec:
      // TODO: implement code execution
      ref.read(aiProvider.notifier).sendMessage(text);
      break;
    default:
      ref.read(aiProvider.notifier).sendMessage(text);
  }
  
  // Auto-scroll
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 300,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });
}
```

### 4. Remove the Chat/Imagine toggle from `_topBar()`

**Remove these lines from the top bar:**
```dart
// DELETE THIS ENTIRE SECTION:
Container(
  padding: const EdgeInsets.all(4),
  decoration: BoxDecoration(/* ... */),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _modeBtn(c, 'Chat', LucideIcons.brain, state.mode == 'chat', ...),
      _modeBtn(c, 'Imagine', LucideIcons.image, state.mode == 'imagine', ...),
    ],
  ),
),
```

**Replace with (optional):**
```dart
// Optional: show current intent hint or just remove entirely
if (state.isGeneratingImage)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.muted.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.wand2, size: 12, color: AppColors.alsamosOrange),
        const SizedBox(width: 6),
        Text('Rasm yaratilmoqda...',
            style: TextStyle(fontSize: 10, color: c.mutedForeground)),
      ],
    ),
  ),
```

### 5. Update the `_emptyState()` description text

**Change from:**
```dart
Text(
  imagine
      ? "Xayolingizni rasmga aylantiring..."
      : "Professional AI yordamchi...",
  // ...
)
```

**To:**
```dart
Text(
  "Professional AI yordamchi. Savol bering, rasm yarating, kod yozing, hujjat tayyorlang yoki har qanday vazifada yordam so'rang.",
  textAlign: TextAlign.center,
  style: TextStyle(fontSize: 13, color: c.mutedForeground, height: 1.5),
)
```

### 6. Update suggestions to reflect unified input

**Add diverse suggestion examples:**
```dart
static const _chatSuggestions = <_Suggestion>[
  _Suggestion(LucideIcons.lightbulb, 'Fikr generatsiya',
      "Yangi g'oyalar yarating",
      "Menga ijtimoiy tarmoq uchun yangi kontent g'oyalarini taklif qil"),
  _Suggestion(LucideIcons.image, 'Rasm yaratish', 
      'Vizual kontent', 
      'Professional portret rasmini chiz: zamonaviy Toshkent fonida'),
  _Suggestion(LucideIcons.code2, 'Kod yozish', 
      'Dasturlashda yordam',
      'React komponent yaratishda yordam ber'),
  _Suggestion(LucideIcons.fileText, 'Hujjat yaratish', 
      'Professional matnlar',
      'Professional biznes hisoboti yozishda yordam ber'),
];
```

## Stub Methods to Implement

Add these placeholder methods to your `_AIPageState`:

```dart
void _showAttachmentPicker() {
  // TODO: Show file picker
  // Use file_picker package or platform file picker
  // Add selected files to attachments list in state
}

void _startVoiceInput() {
  // TODO: Implement voice input
  // Use speech_to_text package
  // Transcribe and populate _input.text
}

void _showModelPicker() {
  // TODO: Show bottom sheet with model options
  showModalBottomSheet(
    context: context,
    builder: (_) => Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(LucideIcons.zap),
            title: const Text('Gemini 3 Flash'),
            subtitle: const Text('Tez va samarali'),
            onTap: () {
              // TODO: update selected model
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.brain),
            title: const Text('Gemini 3 Pro'),
            subtitle: const Text('Murakkab vazifalar uchun'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}
```

## Testing Checklist

After integration:

- [ ] Cold start → input shows unified placeholder
- [ ] Type "draw a cat" → intent hint appears
- [ ] Send → calls `generateImage()` (not `sendMessage()`)
- [ ] Type "hello" → sends as regular chat
- [ ] No Chat/Imagine toggle visible in top bar
- [ ] Send button morphs to stop spinner during generation
- [ ] Multi-line input grows up to 6 lines
- [ ] Intent confirmation dialog appears for low-confidence intents
- [ ] Dark mode renders correctly

## Migration Notes

- **No breaking changes** to existing `AiProvider` — still uses same `sendMessage()` and `generateImage()` methods
- **State management unchanged** — just routing logic changes in UI
- **Backward compatible** — old conversations still work
- The `mode` field in `AiState` is now ignored (but kept for compatibility during transition)

## Next Steps

1. ✅ Integrate composer into existing `ai_page.dart`
2. ⏳ Test intent detection accuracy with real user prompts
3. ⏳ Implement attachment picker
4. ⏳ Implement voice input
5. ⏳ Add video generation backend support
6. ⏳ Add code execution backend support
7. ⏳ Improve intent detection with server-side LLM classification
