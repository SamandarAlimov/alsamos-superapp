/// Shared Communication Component System
///
/// Provides reusable communication primitives (emoji, stickers, GIF, media,
/// voice, uploads, mentions, hashtags, link previews, reactions) that every
/// feature can consume with its own UI while sharing the underlying engine.
library;

export 'emoji/emoji_manager.dart';
export 'emoji/emoji_picker_widget.dart';
export 'stickers/sticker_manager.dart';
export 'stickers/sticker_picker_widget.dart';
export 'gif/gif_manager.dart';
export 'gif/gif_picker_widget.dart';
export 'media/media_picker_manager.dart';
export 'media/media_viewer_widget.dart';
export 'voice/voice_recorder_manager.dart';
export 'voice/voice_player_widget.dart';
export 'upload/upload_manager.dart';
export 'mentions/mention_engine.dart';
export 'mentions/mention_autocomplete_widget.dart';
export 'hashtags/hashtag_engine.dart';
export 'hashtags/hashtag_autocomplete_widget.dart';
export 'link_preview/link_preview_engine.dart';
export 'link_preview/link_preview_widget.dart';
export 'reactions/reaction_manager.dart';
export 'reactions/reaction_bar_widget.dart';
export 'reactions/reaction_chips_widget.dart';
export 'search/communication_search.dart';
