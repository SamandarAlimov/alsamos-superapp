import 'package:flutter/material.dart';

import '../../widgets/music_attachment.dart';
import '../../widgets/poll_display.dart';
import '../../widgets/rich_text_content.dart';

class SharedPostContentSection extends StatelessWidget {
  final String postId;
  final String? content;
  final EdgeInsetsGeometry padding;
  final bool useRichText;
  final int? maxLines;
  final TextStyle? textStyle;
  final VoidCallback? onPollVote;

  const SharedPostContentSection({
    super.key,
    required this.postId,
    required this.content,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 10),
    this.useRichText = true,
    this.maxLines,
    this.textStyle,
    this.onPollVote,
  });

  @override
  Widget build(BuildContext context) {
    final raw = content?.trim();
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    final musicParsed = MusicData.parseFromContent(raw);
    final musicData = musicParsed.$1;
    final pollParsed = PollData.parseFromContent(musicParsed.$2);
    final pollData = pollParsed.$1;
    final cleanContent = pollParsed.$2.trim();

    if (cleanContent.isEmpty && pollData == null && musicData == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cleanContent.isNotEmpty)
          Padding(
            padding: padding,
            child: useRichText
                ? RichTextContent(content: cleanContent)
                : Text(
                    cleanContent,
                    maxLines: maxLines,
                    overflow: maxLines == null ? null : TextOverflow.ellipsis,
                    style: textStyle,
                  ),
          ),
        if (pollData != null)
          Padding(
            padding: padding,
            child: PollDisplay(
              postId: postId,
              pollData: pollData,
              onVote: onPollVote,
            ),
          ),
        if (musicData != null)
          Padding(
            padding: padding,
            child: MusicAttachment(
              music: musicData,
              playbackId: 'post:$postId:music',
            ),
          ),
      ],
    );
  }
}
