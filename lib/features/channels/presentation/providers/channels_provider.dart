import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/channel_model.dart';
import '../../data/channels_repository.dart';

final channelsRepositoryProvider =
    Provider<ChannelsRepository>((ref) => ChannelsRepository());

class ChannelsState {
  final List<Channel> channels;
  final bool isLoading;
  final String? error;
  const ChannelsState({
    this.channels = const [],
    this.isLoading = true,
    this.error,
  });

  ChannelsState copyWith({
    List<Channel>? channels,
    bool? isLoading,
    String? error,
  }) =>
      ChannelsState(
        channels: channels ?? this.channels,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );

  List<Channel> get joined => channels.where((c) => c.isMember).toList();
  List<Channel> get discover => channels.where((c) => !c.isMember).toList();
}

class ChannelsNotifier extends StateNotifier<ChannelsState> {
  ChannelsNotifier(this._repo, this._userId) : super(const ChannelsState()) {
    load();
  }

  final ChannelsRepository _repo;
  final String? _userId;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final channels = await _repo.fetchChannels(_userId);
      state = state.copyWith(channels: channels, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> join(String channelId) async {
    if (_userId == null) return;
    _patch(channelId, isMember: true, delta: 1);
    try {
      await _repo.joinChannel(channelId, _userId);
    } catch (e) {
      _patch(channelId, isMember: false, delta: -1);
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> leave(String channelId) async {
    if (_userId == null) return;
    _patch(channelId, isMember: false, delta: -1);
    try {
      await _repo.leaveChannel(channelId, _userId);
    } catch (e) {
      _patch(channelId, isMember: true, delta: 1);
      state = state.copyWith(error: e.toString());
    }
  }

  Future<Channel?> create(String name, String type,
      {String? description, String? username}) async {
    if (_userId == null) return null;
    final ch = await _repo.createChannel(
        userId: _userId,
        name: name,
        channelType: type,
        description: description,
        username: username);
    if (ch != null) state = state.copyWith(channels: [ch, ...state.channels]);
    return ch;
  }

  Future<void> updatePermissions(
      String channelId, Map<String, bool> permissions) async {
    final current = state.channels;
    state = state.copyWith(
      channels: current
          .map((c) =>
              c.id == channelId ? c.copyWith(adminPermissions: permissions) : c)
          .toList(),
      error: null,
    );
    try {
      await _repo.updateAdminPermissions(channelId, permissions);
    } catch (e) {
      state = state.copyWith(channels: current, error: e.toString());
    }
  }

  void _patch(String channelId, {required bool isMember, required int delta}) {
    state = state.copyWith(
      channels: state.channels
          .map((c) => c.id == channelId
              ? c.copyWith(
                  isMember: isMember,
                  subscriberCount:
                      (c.subscriberCount + delta).clamp(0, 1 << 31))
              : c)
          .toList(),
    );
  }
}

final channelsProvider =
    StateNotifierProvider<ChannelsNotifier, ChannelsState>((ref) {
  final userId = ref.watch(authProvider).user?.id;
  return ChannelsNotifier(ref.watch(channelsRepositoryProvider), userId);
});
