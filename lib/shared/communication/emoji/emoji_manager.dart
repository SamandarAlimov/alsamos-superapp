import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final emojiManagerProvider = Provider<EmojiManager>((ref) => EmojiManager());

class EmojiCategory {
  final String icon;
  final String label;
  final List<String> emojis;
  const EmojiCategory({
    required this.icon,
    required this.label,
    required this.emojis,
  });
}

class EmojiManager {
  static const int maxRecent = 36;
  static const int maxFavorites = 24;

  final ValueNotifier<List<String>> recentEmojis = ValueNotifier([]);
  final ValueNotifier<List<String>> favoriteEmojis = ValueNotifier([]);
  final Map<String, int> _frequency = {};

  void recordUsage(String emoji) {
    _frequency[emoji] = (_frequency[emoji] ?? 0) + 1;
    final list = List<String>.from(recentEmojis.value);
    list.remove(emoji);
    list.insert(0, emoji);
    if (list.length > maxRecent) list.removeLast();
    recentEmojis.value = list;
  }

  void toggleFavorite(String emoji) {
    final list = List<String>.from(favoriteEmojis.value);
    if (list.contains(emoji)) {
      list.remove(emoji);
    } else {
      list.insert(0, emoji);
      if (list.length > maxFavorites) list.removeLast();
    }
    favoriteEmojis.value = list;
  }

  bool isFavorite(String emoji) => favoriteEmojis.value.contains(emoji);

  List<String> get frequentlyUsed {
    final sorted = _frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(24).map((e) => e.key).toList();
  }

  List<String> search(String query) {
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    final results = <String>[];
    for (final cat in categories) {
      for (final emoji in cat.emojis) {
        if (results.length >= 48) return results;
        final name = emojiNames[emoji];
        if (name != null && name.contains(q)) {
          results.add(emoji);
        }
      }
    }
    return results;
  }

  static const List<EmojiCategory> categories = [
    EmojiCategory(icon: '\u{1F600}', label: 'Smileys & People', emojis: _smileys),
    EmojiCategory(icon: '\u{2764}', label: 'Hearts & Symbols', emojis: _hearts),
    EmojiCategory(icon: '\u{1F44D}', label: 'Gestures', emojis: _gestures),
    EmojiCategory(icon: '\u{1F436}', label: 'Animals & Nature', emojis: _animals),
    EmojiCategory(icon: '\u{1F354}', label: 'Food & Drink', emojis: _food),
    EmojiCategory(icon: '\u{26BD}', label: 'Activities', emojis: _activities),
    EmojiCategory(icon: '\u{2708}', label: 'Travel & Places', emojis: _travel),
    EmojiCategory(icon: '\u{1F4A1}', label: 'Objects', emojis: _objects),
    EmojiCategory(icon: '\u{1F3C1}', label: 'Flags', emojis: _flags),
  ];

  static const Map<String, String> emojiNames = {
    '\u{1F600}': 'grinning face',
    '\u{1F603}': 'smiley',
    '\u{1F604}': 'smile',
    '\u{1F601}': 'grin',
    '\u{1F606}': 'laughing',
    '\u{1F605}': 'sweat smile',
    '\u{1F923}': 'rofl',
    '\u{1F602}': 'joy tears',
    '\u{1F642}': 'slightly smiling',
    '\u{1F643}': 'upside down',
    '\u{1F609}': 'wink',
    '\u{1F60A}': 'blush',
    '\u{1F607}': 'innocent angel',
    '\u{1F970}': 'smiling hearts',
    '\u{1F60D}': 'heart eyes',
    '\u{1F929}': 'star struck',
    '\u{1F618}': 'kiss blowing',
    '\u{1F617}': 'kissing',
    '\u{1F61A}': 'kiss closed eyes',
    '\u{1F619}': 'kiss smiling eyes',
    '\u{1F60B}': 'yum delicious',
    '\u{1F61B}': 'tongue stuck out',
    '\u{1F61C}': 'wink tongue',
    '\u{1F92A}': 'zany crazy',
    '\u{1F914}': 'thinking',
    '\u{1F910}': 'zipper mouth',
    '\u{1F928}': 'raised eyebrow',
    '\u{1F610}': 'neutral',
    '\u{1F611}': 'expressionless',
    '\u{1F636}': 'no mouth',
    '\u{1F60F}': 'smirk',
    '\u{1F612}': 'unamused',
    '\u{1F644}': 'eye roll',
    '\u{1F62C}': 'grimacing',
    '\u{1F62A}': 'sleepy',
    '\u{1F634}': 'sleeping',
    '\u{1F637}': 'mask',
    '\u{1F912}': 'thermometer face',
    '\u{1F915}': 'bandage head',
    '\u{1F922}': 'nauseated',
    '\u{1F92E}': 'vomiting',
    '\u{1F927}': 'sneezing',
    '\u{1F975}': 'hot face',
    '\u{1F976}': 'cold face',
    '\u{1F974}': 'woozy dizzy',
    '\u{1F635}': 'dizzy face',
    '\u{1F92F}': 'exploding head mind blown',
    '\u{1F920}': 'cowboy',
    '\u{1F973}': 'party face',
    '\u{1F60E}': 'sunglasses cool',
    '\u{1F913}': 'nerd',
    '\u{1F978}': 'disguised',
    '\u{1F621}': 'angry rage',
    '\u{1F620}': 'angry',
    '\u{1F92C}': 'cursing swearing',
    '\u{1F608}': 'smiling devil',
    '\u{1F47F}': 'angry devil',
    '\u{1F480}': 'skull dead',
    '\u{1F4A9}': 'poop',
    '\u{1F921}': 'clown',
    '\u{1F47B}': 'ghost',
    '\u{1F47D}': 'alien',
    '\u{1F916}': 'robot',
    '\u{2764}': 'red heart love',
    '\u{1F9E1}': 'orange heart',
    '\u{1F49B}': 'yellow heart',
    '\u{1F49A}': 'green heart',
    '\u{1F499}': 'blue heart',
    '\u{1F49C}': 'purple heart',
    '\u{1F90E}': 'brown heart',
    '\u{1F5A4}': 'black heart',
    '\u{1F90D}': 'white heart',
    '\u{1F495}': 'two hearts',
    '\u{1F525}': 'fire hot flame',
    '\u{1F4AF}': 'hundred perfect',
    '\u{1F44D}': 'thumbs up like',
    '\u{1F44E}': 'thumbs down dislike',
    '\u{1F44C}': 'ok perfect',
    '\u{270C}': 'peace victory',
    '\u{1F91E}': 'crossed fingers luck',
    '\u{1F91F}': 'love you gesture',
    '\u{1F918}': 'rock on',
    '\u{1F919}': 'call me shaka',
    '\u{1F44B}': 'wave hello',
    '\u{1F64F}': 'pray thanks',
    '\u{1F4AA}': 'strong muscle flex',
    '\u{1F44F}': 'clap applause',
  };

  static const _smileys = [
    '\u{1F600}','\u{1F603}','\u{1F604}','\u{1F601}','\u{1F606}','\u{1F605}','\u{1F923}','\u{1F602}',
    '\u{1F642}','\u{1F643}','\u{1F609}','\u{1F60A}','\u{1F607}','\u{1F970}','\u{1F60D}','\u{1F929}',
    '\u{1F618}','\u{1F617}','\u{1F61A}','\u{1F619}','\u{1F60B}','\u{1F61B}','\u{1F61C}','\u{1F92A}',
    '\u{1F914}','\u{1F910}','\u{1F928}','\u{1F610}','\u{1F611}','\u{1F636}','\u{1F60F}','\u{1F612}',
    '\u{1F644}','\u{1F62C}','\u{1F62A}','\u{1F634}','\u{1F637}','\u{1F912}','\u{1F915}','\u{1F922}',
    '\u{1F92E}','\u{1F927}','\u{1F975}','\u{1F976}','\u{1F974}','\u{1F635}','\u{1F92F}','\u{1F920}',
    '\u{1F973}','\u{1F60E}','\u{1F913}','\u{1F978}','\u{1F621}','\u{1F620}','\u{1F92C}','\u{1F608}',
    '\u{1F47F}','\u{1F480}','\u{1F4A9}','\u{1F921}','\u{1F47B}','\u{1F47D}','\u{1F916}',
  ];

  static const _hearts = [
    '\u{2764}','\u{1F9E1}','\u{1F49B}','\u{1F49A}','\u{1F499}','\u{1F49C}','\u{1F90E}','\u{1F5A4}','\u{1F90D}',
    '\u{1F495}','\u{1F49E}','\u{1F493}','\u{1F497}','\u{1F496}','\u{1F498}','\u{1F49D}','\u{1F494}',
    '\u{1F525}','\u{2B50}','\u{1F31F}','\u{1F4AB}','\u{2728}','\u{1F4A5}','\u{1F4AF}','\u{1F3B6}',
  ];

  static const _gestures = [
    '\u{1F44D}','\u{1F44E}','\u{1F44C}','\u{270C}','\u{1F91E}','\u{1F91F}','\u{1F918}','\u{1F919}',
    '\u{1F448}','\u{1F449}','\u{1F446}','\u{1F447}','\u{1F44B}','\u{1F91A}','\u{1F590}','\u{270B}',
    '\u{1F596}','\u{1F44A}','\u{270A}','\u{1F44F}','\u{1F64C}','\u{1F450}','\u{1F932}','\u{1F91D}',
    '\u{1F64F}','\u{1F4AA}','\u{1F9B6}','\u{1F9B5}','\u{1F442}','\u{1F443}',
  ];

  static const _animals = [
    '\u{1F436}','\u{1F431}','\u{1F42D}','\u{1F439}','\u{1F430}','\u{1F98A}','\u{1F43B}','\u{1F43C}',
    '\u{1F428}','\u{1F42F}','\u{1F981}','\u{1F42E}','\u{1F437}','\u{1F438}','\u{1F435}','\u{1F648}',
    '\u{1F649}','\u{1F64A}','\u{1F412}','\u{1F414}','\u{1F427}','\u{1F426}','\u{1F985}','\u{1F986}',
    '\u{1F989}','\u{1F987}','\u{1F40A}','\u{1F422}','\u{1F40D}','\u{1F432}',
    '\u{1F335}','\u{1F332}','\u{1F333}','\u{1F334}','\u{1F331}','\u{1F33F}','\u{1F340}','\u{1F338}',
    '\u{1F337}','\u{1F339}','\u{1F33A}','\u{1F33B}','\u{1F33C}','\u{1F490}',
  ];

  static const _food = [
    '\u{1F354}','\u{1F35F}','\u{1F355}','\u{1F32D}','\u{1F32E}','\u{1F32F}','\u{1F37F}','\u{1F361}',
    '\u{1F363}','\u{1F371}','\u{1F359}','\u{1F35A}','\u{1F35B}','\u{1F35C}','\u{1F35D}','\u{1F35E}',
    '\u{1F356}','\u{1F357}','\u{1F358}','\u{1F368}','\u{1F36A}','\u{1F36B}','\u{1F36C}','\u{1F367}',
    '\u{1F370}','\u{1F382}','\u{2615}','\u{1F37A}','\u{1F377}','\u{1F378}','\u{1F379}','\u{1F37D}',
    '\u{1F34E}','\u{1F34F}','\u{1F34A}','\u{1F34B}','\u{1F34C}','\u{1F349}','\u{1F347}','\u{1F353}',
  ];

  static const _activities = [
    '\u{26BD}','\u{1F3C0}','\u{1F3C8}','\u{26BE}','\u{1F3BE}','\u{1F3D0}','\u{1F3C9}','\u{1F3B1}',
    '\u{1F3D3}','\u{1F3F8}','\u{1F3CF}','\u{1F3D2}','\u{26F3}','\u{1F3AF}','\u{1F3B2}','\u{265F}',
    '\u{1F3AE}','\u{1F3B0}','\u{1F3B5}','\u{1F3B6}','\u{1F3A4}','\u{1F3B8}','\u{1F3B9}','\u{1F3BA}',
    '\u{1F941}','\u{1F3AD}','\u{1F3A8}','\u{1F9E9}',
  ];

  static const _travel = [
    '\u{2708}','\u{1F697}','\u{1F695}','\u{1F699}','\u{1F68C}','\u{1F68E}','\u{1F6B2}','\u{1F6F4}',
    '\u{1F6F5}','\u{1F6E5}','\u{1F6A2}','\u{2693}','\u{1F680}','\u{1F6F0}','\u{1F30D}','\u{1F30E}',
    '\u{1F30F}','\u{1F5FA}','\u{1F5FD}','\u{1F3D6}','\u{1F3D4}','\u{1F3DC}','\u{1F3DD}','\u{1F3DE}',
    '\u{1F307}','\u{1F306}','\u{1F309}','\u{1F3DF}','\u{1F3E0}','\u{1F3E2}',
  ];

  static const _objects = [
    '\u{1F4A1}','\u{1F526}','\u{1F56F}','\u{1F4DA}','\u{1F4D6}','\u{1F4DD}','\u{2702}','\u{1F4CE}',
    '\u{1F4CC}','\u{1F4CD}','\u{1F4F1}','\u{1F4BB}','\u{2328}','\u{1F5A8}','\u{1F5B2}','\u{1F4BE}',
    '\u{1F4BF}','\u{1F4C0}','\u{1F39E}','\u{1F3A5}','\u{1F4F7}','\u{1F4F9}','\u{1F4FC}','\u{1F50D}',
    '\u{1F50E}','\u{1F4A3}','\u{1F389}','\u{1F388}','\u{1F381}','\u{1F380}',
    '\u{1F4B0}','\u{1F4B3}','\u{1F4E6}','\u{1F4E8}','\u{1F4E9}','\u{1F511}','\u{1F512}','\u{1F513}',
  ];

  static const _flags = [
    '\u{1F1FA}\u{1F1FF}','\u{1F1FA}\u{1F1F8}','\u{1F1EC}\u{1F1E7}','\u{1F1F7}\u{1F1FA}',
    '\u{1F1E9}\u{1F1EA}','\u{1F1EB}\u{1F1F7}','\u{1F1EF}\u{1F1F5}','\u{1F1F0}\u{1F1F7}',
    '\u{1F1E8}\u{1F1F3}','\u{1F1EE}\u{1F1F3}','\u{1F1E7}\u{1F1F7}','\u{1F1F9}\u{1F1F7}',
    '\u{1F1E6}\u{1F1EA}','\u{1F1F8}\u{1F1E6}','\u{1F1EE}\u{1F1F9}','\u{1F1EA}\u{1F1F8}',
    '\u{1F3C1}','\u{1F3F3}','\u{1F3F4}','\u{1F6A9}',
  ];
}
