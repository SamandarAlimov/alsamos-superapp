import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import 'create_publish_banners.dart';
import 'create_tool_tray.dart';
import 'music_picker.dart';

class CreatePostTab extends StatelessWidget {
  const CreatePostTab({
    super.key,
    required this.colors,
    required this.primary,
    required this.preview,
    required this.identityRow,
    required this.composerField,
    required this.metaInputs,
    required this.fileList,
    required this.onClearSchedule,
    required this.onClearPoll,
    required this.onClearMusic,
    required this.onPickImage,
    required this.onPickVideo,
    required this.onPickFile,
    required this.onCreatePoll,
    required this.onPickMusic,
    this.scheduleLabel,
    this.poll,
    this.musicTrack,
  });

  final AlsamosColors colors;
  final Color primary;
  final Widget preview;
  final Widget identityRow;
  final Widget composerField;
  final Widget metaInputs;
  final Widget fileList;
  final String? scheduleLabel;
  final Map<String, dynamic>? poll;
  final MusicTrack? musicTrack;
  final VoidCallback onClearSchedule;
  final VoidCallback onClearPoll;
  final VoidCallback onClearMusic;
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;
  final VoidCallback onPickFile;
  final VoidCallback onCreatePoll;
  final VoidCallback onPickMusic;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            identityRow,
            const SizedBox(height: 16),
            composerField,
            if (scheduleLabel != null)
              CreateScheduleBanner(
                label: scheduleLabel!,
                primary: primary,
                onClear: onClearSchedule,
              ),
            if (poll != null)
              CreatePollBanner(
                poll: poll!,
                onClear: onClearPoll,
              ),
            if (musicTrack != null)
              CreateMusicBanner(
                track: musicTrack!,
                onClear: onClearMusic,
              ),
            const SizedBox(height: 12),
            metaInputs,
            const SizedBox(height: 14),
            fileList,
            const SizedBox(height: 14),
            CreateToolTray(
              colors: colors,
              onPickImage: onPickImage,
              onPickVideo: onPickVideo,
              onPickFile: onPickFile,
              onCreatePoll: onCreatePoll,
              onPickMusic: onPickMusic,
            ),
          ],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 6, child: preview),
                        const SizedBox(width: 28),
                        Expanded(flex: 5, child: details),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        preview,
                        const SizedBox(height: 24),
                        details,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}
