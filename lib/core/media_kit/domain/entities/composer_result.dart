import 'media_attachment.dart';

class ComposerResult {
  final String text;
  final List<MediaAttachment> attachments;
  final String? replyToId;
  final Map<String, dynamic> metadata;

  const ComposerResult({
    this.text = '',
    this.attachments = const [],
    this.replyToId,
    this.metadata = const {},
  });

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
  bool get hasMedia => attachments.isNotEmpty;
  bool get hasText => text.trim().isNotEmpty;
}
