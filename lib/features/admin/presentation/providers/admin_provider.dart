import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository());

class AdminState {
  final bool isAdmin;
  final bool accessLoading;
  final bool dataLoading;
  final List<VerificationRequest> requests;
  final List<AdminUser> admins;
  final AdminStats stats;
  const AdminState({
    this.isAdmin = false,
    this.accessLoading = true,
    this.dataLoading = false,
    this.requests = const [],
    this.admins = const [],
    this.stats = const AdminStats(),
  });

  AdminState copyWith({
    bool? isAdmin,
    bool? accessLoading,
    bool? dataLoading,
    List<VerificationRequest>? requests,
    List<AdminUser>? admins,
    AdminStats? stats,
  }) =>
      AdminState(
        isAdmin: isAdmin ?? this.isAdmin,
        accessLoading: accessLoading ?? this.accessLoading,
        dataLoading: dataLoading ?? this.dataLoading,
        requests: requests ?? this.requests,
        admins: admins ?? this.admins,
        stats: stats ?? this.stats,
      );

  List<VerificationRequest> get pending => requests.where((r) => r.status == 'pending').toList();
  List<VerificationRequest> get processed => requests.where((r) => r.status != 'pending').toList();
}

class AdminNotifier extends StateNotifier<AdminState> {
  AdminNotifier(this._repo, this._userId) : super(const AdminState()) {
    _init();
  }
  final AdminRepository _repo;
  final String? _userId;

  Future<void> _init() async {
    if (_userId == null) {
      state = state.copyWith(accessLoading: false, isAdmin: false);
      return;
    }
    try {
      final admin = await _repo.isAdmin(_userId);
      state = state.copyWith(isAdmin: admin, accessLoading: false);
      if (admin) await refresh();
    } catch (_) {
      state = state.copyWith(accessLoading: false, isAdmin: false);
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(dataLoading: true);
    try {
      final results = await Future.wait<Object>([
        _repo.fetchRequests(),
        _repo.fetchAdmins(),
        _repo.fetchStats(),
      ]);
      state = state.copyWith(
        requests: results[0] as List<VerificationRequest>,
        admins: results[1] as List<AdminUser>,
        stats: results[2] as AdminStats,
        dataLoading: false,
      );
    } catch (_) {
      state = state.copyWith(dataLoading: false);
    }
  }

  Future<void> approve(VerificationRequest req) async {
    final uid = _userId;
    if (uid == null) return;
    await _repo.approve(req, uid);
    await refresh();
  }

  Future<void> reject(VerificationRequest req, String reason) async {
    final uid = _userId;
    if (uid == null) return;
    await _repo.reject(req, uid, reason);
    await refresh();
  }

  Future<String?> addAdmin(String username) async {
    final uid = _userId;
    if (uid == null) return 'Not signed in';
    final err = await _repo.grantAdminByUsername(username, uid);
    if (err == null) await refresh();
    return err;
  }

  Future<void> removeAdmin(String userId) async {
    if (userId == _userId) return;
    await _repo.revokeAdmin(userId);
    await refresh();
  }
}

final adminProvider = StateNotifierProvider<AdminNotifier, AdminState>((ref) {
  final userId = ref.watch(authProvider).user?.id;
  return AdminNotifier(ref.watch(adminRepositoryProvider), userId);
});
