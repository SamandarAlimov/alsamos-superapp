/// Alsamos AI qobiliyatlari — web repo bilan bir xil kontrakt.
///
/// Manba (source of truth): socialalsamos `src/lib/ai/capabilities.ts`
/// va `docs/AI_PLATFORM_SPEC.md`. Bu faylni o'zgartirsangiz, web reposini ham
/// bir vaqtda yangilang (parity majburiy).
const String aiContractVersion = '1.0.0';

/// Vosita guruhlari.
enum ToolGroupId { web, image, video, code, alsamos, connectors, computer }

/// Model tanlovi (server `MODEL_ROUTES` bilan mos).
enum ModelId { auto, fast, balanced, coding, reasoning, vision }

/// Ishlash rejimi.
enum AIMode { chat, agent }

String toolGroupIdToJson(ToolGroupId id) => id.name;
String modelIdToJson(ModelId id) => id.name;
String aiModeToJson(AIMode mode) => mode.name;

ToolGroupId? toolGroupIdFromJson(String value) {
  for (final id in ToolGroupId.values) {
    if (id.name == value) return id;
  }
  return null;
}

ModelId modelIdFromJson(String? value) {
  for (final id in ModelId.values) {
    if (id.name == value) return id;
  }
  return ModelId.auto;
}

AIMode aiModeFromJson(String? value) =>
    value == 'agent' ? AIMode.agent : AIMode.chat;

class ToolGroup {
  const ToolGroup({
    required this.id,
    required this.label,
    required this.description,
    required this.tools,
    this.defaultOn = false,
    this.sensitive = false,
  });

  final ToolGroupId id;
  final String label;
  final String description;
  final List<String> tools;
  final bool defaultOn;
  final bool sensitive;
}

const List<ToolGroup> kToolGroups = <ToolGroup>[
  ToolGroup(
    id: ToolGroupId.web,
    label: 'Internet',
    description: "Qidiruv va sahifa o'qish — manbalar bilan javob",
    tools: <String>['web_search', 'web_fetch'],
    defaultOn: true,
  ),
  ToolGroup(
    id: ToolGroupId.image,
    label: 'Rasm',
    description: 'Matn asosida rasm generatsiya qilish',
    tools: <String>['generate_image'],
    defaultOn: true,
  ),
  ToolGroup(
    id: ToolGroupId.video,
    label: 'Video',
    description: "Qisqa video navbatga qo'yiladi",
    tools: <String>['generate_video'],
  ),
  ToolGroup(
    id: ToolGroupId.code,
    label: 'Kod',
    description: "Kod yozish va xavfsiz sandbox'da ishga tushirish",
    tools: <String>['run_code'],
    defaultOn: true,
  ),
  ToolGroup(
    id: ToolGroupId.alsamos,
    label: 'Alsamos',
    description: 'Postlar, marketplace va xotira',
    tools: <String>['search_posts', 'search_marketplace', 'remember'],
    defaultOn: true,
  ),
  ToolGroup(
    id: ToolGroupId.connectors,
    label: 'Konnektorlar (MCP)',
    description: 'Ulangan MCP serverlari vositalari',
    tools: <String>['list_connector_tools', 'connector_call'],
  ),
  ToolGroup(
    id: ToolGroupId.computer,
    label: 'Kompyuter',
    description: 'Alsamos Bridge orqali qurilmani boshqarish (tasdiq bilan)',
    tools: <String>['computer_task', 'computer_task_result'],
    sensitive: true,
  ),
];

const List<ToolGroupId> kDefaultToolGroups = <ToolGroupId>[
  ToolGroupId.web,
  ToolGroupId.image,
  ToolGroupId.code,
  ToolGroupId.alsamos,
];

class ModelOption {
  const ModelOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final ModelId id;
  final String label;
  final String description;
}

const List<ModelOption> kModelOptions = <ModelOption>[
  ModelOption(
    id: ModelId.auto,
    label: 'Avto',
    description: 'Vazifaga qarab eng mos model tanlanadi',
  ),
  ModelOption(id: ModelId.fast, label: 'Tezkor', description: 'Qisqa savollar uchun'),
  ModelOption(
    id: ModelId.balanced,
    label: 'Balans',
    description: 'Sifat va tezlik muvozanati',
  ),
  ModelOption(id: ModelId.coding, label: 'Kodlash', description: 'Dasturlash vazifalari'),
  ModelOption(
    id: ModelId.reasoning,
    label: 'Chuqur fikrlash',
    description: 'Murakkab tahlil va reja',
  ),
  ModelOption(id: ModelId.vision, label: 'Vizual', description: 'Rasm va fayl tahlili'),
];

class ModeOption {
  const ModeOption({required this.id, required this.label, required this.hint});

  final AIMode id;
  final String label;
  final String hint;
}

const List<ModeOption> kModeOptions = <ModeOption>[
  ModeOption(id: AIMode.chat, label: 'Suhbat', hint: 'Tezkor javoblar, kerak bo\u2019lsa vositalar'),
  ModeOption(
    id: AIMode.agent,
    label: 'Agent',
    hint: 'Ko\u2019p qadamli vazifalarni o\u2019zi bajaradi',
  ),
];

const Map<String, String> kToolLabels = <String, String>{
  'web_search': 'Internetdan qidirmoqda',
  'web_fetch': "Sahifani o'qimoqda",
  'generate_image': 'Rasm yaratmoqda',
  'generate_video': 'Video yaratmoqda',
  'run_code': 'Kodni ishga tushirmoqda',
  'search_posts': 'Postlarni qidirmoqda',
  'search_marketplace': "Bozorni ko'rmoqda",
  'remember': 'Eslab qolmoqda',
  'list_connector_tools': "Konnektor vositalarini o'qimoqda",
  'connector_call': 'Konnektorni chaqirmoqda',
  'computer_task': 'Kompyuter vazifasini tayyorlamoqda',
  'computer_task_result': 'Vazifa natijasini olmoqda',
};

String toolLabel(String name) => kToolLabels[name] ?? name;

/// Agent rejimida barcha ruxsat etilgan guruhlar yoqiladi (sezgirlaridan tashqari
/// foydalanuvchi tanloviga hurmat qilinadi).
List<ToolGroupId> groupsForMode(AIMode mode, List<ToolGroupId> selected) {
  if (mode != AIMode.agent) return selected;
  final result = <ToolGroupId>{...selected};
  for (final group in kToolGroups) {
    if (!group.sensitive) result.add(group.id);
  }
  return result.toList();
}
