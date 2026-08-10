import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../features/home/data/models/post_model.dart';

String formatCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return '$count';
}

String formatPostTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inHours < 24) return timeago.format(d);
  return DateFormat('MMM d').format(d);
}

String collaboratorTitle(List<PostCollaborator> collaborators) {
  if (collaborators.isEmpty) return '';
  final first = collaborators.first.label;
  if (collaborators.length == 1) return ' va $first';
  return ' va $first +${collaborators.length - 1}';
}

String collaboratorSubtitle(List<PostCollaborator> collaborators) {
  if (collaborators.isEmpty) return '';
  final first = collaborators.first.username?.trim();
  if (first == null || first.isEmpty) return 'bilan';
  if (collaborators.length == 1) return '@$first bilan';
  return '@$first +${collaborators.length - 1} bilan';
}
