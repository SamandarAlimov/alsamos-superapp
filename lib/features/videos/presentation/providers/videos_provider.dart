import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/data/models/post_model.dart';
import '../../data/video_repository.dart';

final videoRepositoryProvider = Provider((ref) => const VideoRepository());

final videosProvider = FutureProvider<List<Post>>((ref) {
  return ref.read(videoRepositoryProvider).fetchVideos();
});
