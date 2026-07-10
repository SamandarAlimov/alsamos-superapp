import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/order_models.dart';
import '../../data/orders_repository.dart';

final ordersRepositoryProvider = Provider((ref) => OrdersRepository());

class OrdersState {
  final bool isLoading;
  final List<OrderModel> orders;
  final List<OrderModel> sales;
  final String? error;
  const OrdersState({
    this.isLoading = true,
    this.orders = const [],
    this.sales = const [],
    this.error,
  });

  OrdersState copyWith({bool? isLoading, List<OrderModel>? orders, List<OrderModel>? sales, String? error}) =>
      OrdersState(
        isLoading: isLoading ?? this.isLoading,
        orders: orders ?? this.orders,
        sales: sales ?? this.sales,
        error: error,
      );
}

class OrdersNotifier extends StateNotifier<OrdersState> {
  OrdersNotifier(this.ref) : super(const OrdersState()) {
    refresh();
  }
  final Ref ref;

  Future<void> refresh() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) {
      state = state.copyWith(isLoading: false);
      return;
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final repo = ref.read(ordersRepositoryProvider);
      final orders = await repo.fetchMyOrders(userId);
      final sales = await repo.fetchMySales(userId);
      state = state.copyWith(isLoading: false, orders: orders, sales: sales);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> updateStatus(String orderId, String status) async {
    await ref.read(ordersRepositoryProvider).updateStatus(orderId, status);
    await refresh();
  }
}

final ordersProvider =
    StateNotifierProvider<OrdersNotifier, OrdersState>((ref) => OrdersNotifier(ref));
