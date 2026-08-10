import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/conversation_admin_model.dart';
import '../../data/repositories/conversation_admin_repository.dart';

final conversationAdminRepositoryProvider =
    Provider((ref) => const ConversationAdminRepository());

final conversationMembersProvider = FutureProvider.family
    .autoDispose<List<ConversationMember>, String>((ref, conversationId) {
  return ref
      .read(conversationAdminRepositoryProvider)
      .fetchMembers(conversationId);
});

final conversationRestrictionsProvider = FutureProvider.family
    .autoDispose<List<ConversationRestriction>, String>((ref, conversationId) {
  return ref
      .read(conversationAdminRepositoryProvider)
      .fetchRestrictions(conversationId);
});

final conversationAdminLogProvider = FutureProvider.family
    .autoDispose<List<ConversationAdminAction>, String>((ref, conversationId) {
  return ref
      .read(conversationAdminRepositoryProvider)
      .fetchAdminLog(conversationId);
});

final conversationReportsProvider = FutureProvider.family
    .autoDispose<List<ReportedMessage>, String>((ref, conversationId) {
  return ref
      .read(conversationAdminRepositoryProvider)
      .fetchReports(conversationId);
});

final conversationStatsProvider = FutureProvider.family
    .autoDispose<ConversationStats, String>((ref, conversationId) {
  return ref
      .read(conversationAdminRepositoryProvider)
      .fetchStats(conversationId);
});
