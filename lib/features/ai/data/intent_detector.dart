import 'package:flutter/material.dart';
import 'ai_models_v2.dart';

/// Client-side intent detection using heuristic pattern matching.
/// This is MVP implementation — production should use server-side LLM classification
/// via /api/v1/ai/detect-intent endpoint for better accuracy.
class IntentDetector {
  /// Detect the user's intent from their prompt
  static DetectedIntent detect(String prompt) {
    final lower = prompt.toLowerCase().trim();

    // Empty or very short prompts default to chat
    if (lower.isEmpty || lower.length < 3) {
      return const DetectedIntent(type: IntentType.chat, confidence: 1.0);
    }

    // ── Image Generation ──────────────────────────────────────────────────────
    if (_matchesImageGeneration(lower)) {
      return DetectedIntent(
        type: IntentType.imageGen,
        confidence: 0.85,
        parameters: {'prompt': prompt},
      );
    }

    // ── Video Generation ──────────────────────────────────────────────────────
    if (_matchesVideoGeneration(lower)) {
      return DetectedIntent(
        type: IntentType.videoGen,
        confidence: 0.8,
        parameters: {'prompt': prompt},
      );
    }

    // ── Code Execution (user saying "run this") ──────────────────────────────
    if (_matchesCodeExecution(lower, prompt)) {
      return DetectedIntent(
        type: IntentType.codeExec,
        confidence: 0.9,
        parameters: {'code': _extractCodeBlock(prompt)},
      );
    }

    // ── Code Generation ───────────────────────────────────────────────────────
    if (_matchesCodeGeneration(lower)) {
      return DetectedIntent(
        type: IntentType.codeGen,
        confidence: 0.75,
        parameters: {'description': prompt},
      );
    }

    // ── Document Generation ───────────────────────────────────────────────────
    if (_matchesDocumentGeneration(lower)) {
      return DetectedIntent(
        type: IntentType.documentGen,
        confidence: 0.7,
        parameters: {'instructions': prompt},
      );
    }

    // ── Spreadsheet Generation ────────────────────────────────────────────────
    if (_matchesSpreadsheetGeneration(lower)) {
      return DetectedIntent(
        type: IntentType.spreadsheetGen,
        confidence: 0.7,
        parameters: {'instructions': prompt},
      );
    }

    // ── Web Search ────────────────────────────────────────────────────────────
    if (_matchesWebSearch(lower)) {
      return DetectedIntent(
        type: IntentType.webSearch,
        confidence: 0.8,
        parameters: {'query': prompt},
      );
    }

    // ── Translation ───────────────────────────────────────────────────────────
    if (_matchesTranslation(lower)) {
      return DetectedIntent(
        type: IntentType.translate,
        confidence: 0.85,
        parameters: {'text': prompt},
      );
    }

    // ── Summarization ─────────────────────────────────────────────────────────
    if (_matchesSummarization(lower)) {
      return DetectedIntent(
        type: IntentType.summarize,
        confidence: 0.8,
        parameters: {'text': prompt},
      );
    }

    // ── Default to Chat ───────────────────────────────────────────────────────
    return const DetectedIntent(
      type: IntentType.chat,
      confidence: 0.6,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Pattern Matching Functions
  // ═══════════════════════════════════════════════════════════════════════════

  static bool _matchesImageGeneration(String lower) {
    // English keywords
    final englishPatterns = [
      r'\b(draw|paint|sketch|illustrate|visuali[sz]e)\b',
      r'\b(generate|create|make|design|produce).*\b(image|picture|photo|illustration|artwork|graphic)\b',
      r'\bimage.*of\b',
      r'\bpicture.*of\b',
    ];

    // Uzbek keywords (Latin)
    final uzbekPatterns = [
      r'\b(rasm|surat|tasvir|chiz)\b',
      r'\b(yarat|tuz|chiq|chiqar).*\b(rasm|surat|tasvir)\b',
      r'\brasm.*chiz\b',
    ];

    // Russian keywords
    final russianPatterns = [
      r'\b(рисунок|картин[ау]|изображени[ея]|иллюстраци[юя])\b',
      r'\b(нарисуй|создай|сгенерируй).*\b(рисунок|картину|изображение)\b',
    ];

    return _matchesAnyPattern(
        lower, [...englishPatterns, ...uzbekPatterns, ...russianPatterns]);
  }

  static bool _matchesVideoGeneration(String lower) {
    final patterns = [
      r'\b(create|generate|make|produce).*\b(video|animation|clip)\b',
      r'\bvideo.*of\b',
      r'\banimate\b',
      r'\b(video|animatsiya).*\b(yarat|tuz)\b',
      r'\b(создай|сгенерируй).*\bвидео\b',
    ];
    return _matchesAnyPattern(lower, patterns);
  }

  static bool _matchesCodeExecution(String lower, String original) {
    // Check if prompt contains code block
    final hasCodeBlock = original.contains('```');

    // Check for execution keywords
    final patterns = [
      r'\b(run|execute|eval|interpret|launch)\b',
      r'\bishla\b', // Uzbek: run
      r'\b(запусти|выполни|исполни)\b', // Russian
    ];

    return hasCodeBlock && _matchesAnyPattern(lower, patterns);
  }

  static bool _matchesCodeGeneration(String lower) {
    final patterns = [
      r'\b(write|create|generate|implement|build|code|program)\b.*\b(function|class|component|script|program|app|application)\b',
      r'\bfunction.*to\b',
      r'\bclass.*that\b',
      r'\bkomponent.*yoz\b', // Uzbek: write component
      r'\b(напиши|создай|реализуй).*\b(функци[юя]|класс|компонент|программу)\b',
    ];
    return _matchesAnyPattern(lower, patterns);
  }

  static bool _matchesDocumentGeneration(String lower) {
    final patterns = [
      r'\b(write|draft|compose|create|generate).*\b(document|report|article|essay|letter|email|memo|proposal)\b',
      r'\bdocument.*about\b',
      r'\breport.*on\b',
      r'\b(yoz|tuz).*\b(hujjat|hisobot|xat|maqola)\b',
      r'\b(напиши|составь|создай).*\b(документ|отчёт|статью|письмо)\b',
    ];
    return _matchesAnyPattern(lower, patterns);
  }

  static bool _matchesSpreadsheetGeneration(String lower) {
    final patterns = [
      r'\b(create|generate|make|build).*\b(spreadsheet|table|excel|csv)\b',
      r'\bspreadsheet.*with\b',
      r'\btable.*showing\b',
      r'\bjadval.*yarat\b', // Uzbek: create table
      r'\b(создай|сгенерируй).*\b(таблиц[уа]|excel)\b',
    ];
    return _matchesAnyPattern(lower, patterns);
  }

  static bool _matchesWebSearch(String lower) {
    final patterns = [
      r'^\b(search|find|look up|google|what is|what are|who is|when|where)\b',
      r"\b(latest|current|recent|today's|this week's|this month's)\b",
      r'\bqidirish\b', // Uzbek: search
      r'\b(найди|поищи|что такое|кто такой|когда)\b', // Russian
    ];
    return _matchesAnyPattern(lower, patterns);
  }

  static bool _matchesTranslation(String lower) {
    final patterns = [
      r'\b(translate|translat[ei]|convert).*\b(to|into|in)\b',
      r'\btranslate.*from\b',
      r'\b(tarjima|tarjima qil)\b', // Uzbek
      r'\b(переведи|перевод|переводи)\b', // Russian
      r'\b(english|russian|uzbek|spanish|french|german|chinese|arabic)\b.*\b(english|russian|uzbek|spanish|french|german|chinese|arabic)\b',
    ];
    return _matchesAnyPattern(lower, patterns);
  }

  static bool _matchesSummarization(String lower) {
    final patterns = [
      r'\b(summari[sz]e|condense|brief|tldr|recap|overview)\b',
      r'\bin short\b',
      r'\bkey points\b',
      r'\b(qisqacha|qisqa|xulosa)\b', // Uzbek
      r'\b(кратко|резюме|краткое содержание|вкратце)\b', // Russian
    ];
    return _matchesAnyPattern(lower, patterns);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Helper Functions
  // ═══════════════════════════════════════════════════════════════════════════

  static bool _matchesAnyPattern(String text, List<String> patterns) {
    for (final pattern in patterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(text)) {
        return true;
      }
    }
    return false;
  }

  static String? _extractCodeBlock(String text) {
    final match = RegExp(r'```[\w]*\n?([\s\S]*?)\n?```').firstMatch(text);
    return match?.group(1)?.trim();
  }

  /// Get a human-readable description of the detected intent
  static String getIntentDescription(IntentType type) {
    switch (type) {
      case IntentType.chat:
        return 'Suhbat';
      case IntentType.imageGen:
        return 'Rasm yaratish';
      case IntentType.videoGen:
        return 'Video yaratish';
      case IntentType.codeGen:
        return 'Kod yozish';
      case IntentType.codeExec:
        return 'Kodni ishga tushirish';
      case IntentType.documentGen:
        return 'Hujjat yaratish';
      case IntentType.spreadsheetGen:
        return 'Jadval yaratish';
      case IntentType.webSearch:
        return 'Internetdan qidirish';
      case IntentType.translate:
        return 'Tarjima';
      case IntentType.summarize:
        return 'Xulosa';
    }
  }

  /// Get an icon for the intent type (codePoint for MaterialIcons)
  static IconData getIntentIconData(IntentType type) {
    switch (type) {
      case IntentType.chat:
        return Icons.chat;
      case IntentType.imageGen:
        return Icons.image;
      case IntentType.videoGen:
        return Icons.videocam;
      case IntentType.codeGen:
        return Icons.code;
      case IntentType.codeExec:
        return Icons.play_arrow;
      case IntentType.documentGen:
        return Icons.description;
      case IntentType.spreadsheetGen:
        return Icons.table_chart;
      case IntentType.webSearch:
        return Icons.search;
      case IntentType.translate:
        return Icons.translate;
      case IntentType.summarize:
        return Icons.summarize;
    }
  }

  /// Get an icon for the intent type (codePoint for MaterialIcons)
  static int getIntentIcon(IntentType type) {
    return getIntentIconData(type).codePoint;
  }
}
