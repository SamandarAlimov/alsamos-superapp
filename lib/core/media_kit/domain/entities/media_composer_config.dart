enum MediaComposerContext { comment, chat, postCaption, bio, feedback }

class MediaComposerConfig {
  final bool allowAudio;
  final bool allowVideo;
  final bool allowImage;
  final bool allowGif;
  final bool allowStickers;
  final bool allowAnimatedEmoji;
  final bool allowReplyPreview;
  final bool allowMentions;
  final bool allowHashtags;
  final bool allowPolls;
  final bool allowLocation;
  final bool allowFileDocument;
  final bool allowVideoNote;
  final int? maxVideoDurationSeconds;
  final int? maxAudioDurationSeconds;
  final String hintText;
  final MediaComposerContext context;

  const MediaComposerConfig({
    this.allowAudio = true,
    this.allowVideo = true,
    this.allowImage = true,
    this.allowGif = true,
    this.allowStickers = true,
    this.allowAnimatedEmoji = true,
    this.allowReplyPreview = false,
    this.allowMentions = false,
    this.allowHashtags = false,
    this.allowPolls = false,
    this.allowLocation = false,
    this.allowFileDocument = false,
    this.allowVideoNote = false,
    this.maxVideoDurationSeconds,
    this.maxAudioDurationSeconds,
    this.hintText = 'Xabar yozing...',
    this.context = MediaComposerContext.chat,
  });

  static const comment = MediaComposerConfig(
    allowAudio: true,
    allowVideo: true,
    allowImage: true,
    allowGif: true,
    allowStickers: true,
    allowAnimatedEmoji: true,
    allowReplyPreview: true,
    allowMentions: true,
    allowHashtags: true,
    allowPolls: false,
    allowLocation: false,
    allowFileDocument: false,
    allowVideoNote: false,
    hintText: 'Izoh qo\'shing...',
    context: MediaComposerContext.comment,
  );

  static const chat = MediaComposerConfig(
    allowAudio: true,
    allowVideo: true,
    allowImage: true,
    allowGif: true,
    allowStickers: true,
    allowAnimatedEmoji: true,
    allowReplyPreview: true,
    allowMentions: true,
    allowHashtags: true,
    allowPolls: true,
    allowLocation: true,
    allowFileDocument: true,
    allowVideoNote: true,
    hintText: 'Xabar...',
    context: MediaComposerContext.chat,
  );

  static const bio = MediaComposerConfig(
    allowAudio: false,
    allowVideo: false,
    allowImage: false,
    allowGif: false,
    allowStickers: false,
    allowAnimatedEmoji: true,
    allowReplyPreview: false,
    allowMentions: false,
    allowHashtags: false,
    allowPolls: false,
    allowLocation: false,
    allowFileDocument: false,
    allowVideoNote: false,
    hintText: 'Bio...',
    context: MediaComposerContext.bio,
  );

  bool get hasMediaOptions =>
      allowAudio || allowVideo || allowImage || allowFileDocument;

  bool get hasExpressionOptions =>
      allowGif || allowStickers || allowAnimatedEmoji;
}
