import 'package:flutter/material.dart';

import 'for_you_section.dart';
import 'popular_creators.dart';
import 'trending_hashtags.dart';
import 'trending_videos.dart';

export 'for_you_section.dart';
export 'popular_creators.dart';
export 'trending_hashtags.dart';
export 'trending_videos.dart';

// Composite scrollable feed for the Discover/Explore tab — stitches
// trending hashtags, popular creators, trending videos, and the for-you grid
// in the exact order the web app renders them.
class DiscoverySections extends StatelessWidget {
  const DiscoverySections({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: const [
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: TrendingHashtags()),
        SizedBox(height: 18),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: PopularCreators()),
        SizedBox(height: 18),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: TrendingVideos()),
        SizedBox(height: 18),
        Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: ForYouSection()),
        SizedBox(height: 18),
      ],
    );
  }
}
