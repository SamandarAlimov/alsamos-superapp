// Payment gateway abstraction for external payments (Click, Payme, cards)
// Implementations handle provider-specific API calls and webhook verification

import 'dart:async';

/// Abstract payment gateway provider interface
abstract class PaymentGatewayProvider {
  String get name; // 'click', 'payme', 'uzcard', 'visa', etc.
  
  /// Initialize payment and return payment URL for redirect
  Future<PaymentInitResult> initializePayment({
    required String orderId,
    required double amount,
    required String currency,
    required String returnUrl,
    Map<String, dynamic>? metadata,
  });
  
  /// Check payment status
  Future<PaymentStatusResult> checkPaymentStatus(String transactionId);
  
  /// Verify webhook callback (server-side signature validation)
  Future<bool> verifyWebhook(Map<String, dynamic> payload, String? signature);
}

/// Payment initialization result
class PaymentInitResult {
  final bool success;
  final String? error;
  final String? paymentUrl; // URL to redirect user for payment
  final String? transactionId; // Gateway transaction ID
  final Map<String, dynamic>? metadata;

  const PaymentInitResult({
    required this.success,
    this.error,
    this.paymentUrl,
    this.transactionId,
    this.metadata,
  });

  factory PaymentInitResult.success({
    required String paymentUrl,
    required String transactionId,
    Map<String, dynamic>? metadata,
  }) =>
      PaymentInitResult(
        success: true,
        paymentUrl: paymentUrl,
        transactionId: transactionId,
        metadata: metadata,
      );

  factory PaymentInitResult.failure(String error) =>
      PaymentInitResult(success: false, error: error);
}

/// Payment status check result
class PaymentStatusResult {
  final bool success;
  final String? error;
  final String status; // 'pending', 'processing', 'completed', 'failed', 'cancelled'
  final Map<String, dynamic>? metadata;

  const PaymentStatusResult({
    required this.success,
    this.error,
    required this.status,
    this.metadata,
  });

  factory PaymentStatusResult.success({
    required String status,
    Map<String, dynamic>? metadata,
  }) =>
      PaymentStatusResult(success: true, status: status, metadata: metadata);

  factory PaymentStatusResult.failure(String error) =>
      PaymentStatusResult(success: false, error: error, status: 'failed');
}

// ============================================================================
// CLICK PROVIDER (Uzbekistan)
// ============================================================================

class ClickPaymentProvider implements PaymentGatewayProvider {
  final String merchantId;
  final String serviceId;
  final String baseUrl;

  ClickPaymentProvider({
    required this.merchantId,
    required this.serviceId,
    this.baseUrl = 'https://my.click.uz/services/pay',
  });

  @override
  String get name => 'click';

  @override
  Future<PaymentInitResult> initializePayment({
    required String orderId,
    required double amount,
    required String currency,
    required String returnUrl,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (amount <= 0) return PaymentInitResult.failure('invalid_amount');
      final amountTiyin = (amount * 100).toInt();

      final paymentUrl = Uri.parse(baseUrl).replace(queryParameters: {
        'service_id': serviceId,
        'merchant_id': merchantId,
        'amount': amountTiyin.toString(),
        'transaction_param': orderId,
        'return_url': returnUrl,
      }).toString();

      return PaymentInitResult.success(
        paymentUrl: paymentUrl,
        transactionId: orderId,
        metadata: {'provider': 'click', 'amount_tiyin': amountTiyin},
      );
    } catch (e) {
      return PaymentInitResult.failure(e.toString());
    }
  }

  @override
  Future<PaymentStatusResult> checkPaymentStatus(String transactionId) async {
    // Click doesn't have a direct status check API
    // Status comes via webhook
    return PaymentStatusResult.success(status: 'pending');
  }

  @override
  Future<bool> verifyWebhook(Map<String, dynamic> payload, String? signature) async {
    // Webhook signature verification is handled server-side in
    // supabase/functions/payment-webhook/index.ts for security.
    // Client never sees secret keys. This method is not used client-side.
    throw UnimplementedError(
      'Webhook verification must be done server-side in payment-webhook Edge Function',
    );
  }
}

// ============================================================================
// PAYME PROVIDER (Uzbekistan)
// ============================================================================

class PaymePaymentProvider implements PaymentGatewayProvider {
  final String merchantId;
  final String baseUrl;

  PaymePaymentProvider({
    required this.merchantId,
    this.baseUrl = 'https://checkout.paycom.uz',
  });

  @override
  String get name => 'payme';

  @override
  Future<PaymentInitResult> initializePayment({
    required String orderId,
    required double amount,
    required String currency,
    required String returnUrl,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      if (amount <= 0) return PaymentInitResult.failure('invalid_amount');
      final sanitizedOrderId = orderId.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '');
      if (sanitizedOrderId.isEmpty || sanitizedOrderId != orderId) {
        return PaymentInitResult.failure('invalid_order_id');
      }
      final amountTiyin = (amount * 100).toInt();
      final sanitizedReturnUrl = Uri.encodeComponent(returnUrl);

      final params =
          'm=$merchantId;ac.order_id=$sanitizedOrderId;a=$amountTiyin;c=$sanitizedReturnUrl';
      final encodedParams = Uri.encodeComponent(params);

      final paymentUrl = '$baseUrl/$encodedParams';

      return PaymentInitResult.success(
        paymentUrl: paymentUrl,
        transactionId: sanitizedOrderId,
        metadata: {'provider': 'payme'},
      );
    } catch (e) {
      return PaymentInitResult.failure(e.toString());
    }
  }

  @override
  Future<PaymentStatusResult> checkPaymentStatus(String transactionId) async {
    // Payme uses JSON-RPC API for status checks
    // Should be called from server-side (Edge Function)
    return PaymentStatusResult.success(status: 'pending');
  }

  @override
  Future<bool> verifyWebhook(Map<String, dynamic> payload, String? signature) async {
    // Webhook signature verification is handled server-side in
    // supabase/functions/payment-webhook/index.ts for security.
    // Client never sees secret keys. This method is not used client-side.
    throw UnimplementedError(
      'Webhook verification must be done server-side in payment-webhook Edge Function',
    );
  }
}

// ============================================================================
// UZCARD PROVIDER (Uzbekistan)
// ============================================================================

class UzcardPaymentProvider implements PaymentGatewayProvider {
  final String merchantId;
  final String terminalId;
  final String baseUrl;

  UzcardPaymentProvider({
    required this.merchantId,
    required this.terminalId,
    this.baseUrl = 'https://api.uzcard.uz',
  });

  @override
  String get name => 'uzcard';

  @override
  Future<PaymentInitResult> initializePayment({
    required String orderId,
    required double amount,
    required String currency,
    required String returnUrl,
    Map<String, dynamic>? metadata,
  }) async {
    if (amount <= 0) return PaymentInitResult.failure('invalid_amount');
    return PaymentInitResult.failure('uzcard_requires_edge_function');
  }

  @override
  Future<PaymentStatusResult> checkPaymentStatus(String transactionId) async {
    return PaymentStatusResult.success(status: 'pending');
  }

  @override
  Future<bool> verifyWebhook(Map<String, dynamic> payload, String? signature) async {
    throw UnimplementedError(
      'Webhook verification must be done server-side in payment-webhook Edge Function',
    );
  }
}

// ============================================================================
// CARD PROVIDER (Visa/Mastercard via aggregator)
// ============================================================================

class CardPaymentProvider implements PaymentGatewayProvider {
  final String apiKey;
  final String baseUrl;

  CardPaymentProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.payment-aggregator.com',
  });

  @override
  String get name => 'card';

  @override
  Future<PaymentInitResult> initializePayment({
    required String orderId,
    required double amount,
    required String currency,
    required String returnUrl,
    Map<String, dynamic>? metadata,
  }) async {
    if (amount <= 0) return PaymentInitResult.failure('invalid_amount');
    return PaymentInitResult.failure('card_requires_edge_function');
  }

  @override
  Future<PaymentStatusResult> checkPaymentStatus(String transactionId) async {
    return PaymentStatusResult.success(status: 'pending');
  }

  @override
  Future<bool> verifyWebhook(Map<String, dynamic> payload, String? signature) async {
    throw UnimplementedError(
      'Webhook verification must be done server-side in payment-webhook Edge Function',
    );
  }
}

// ============================================================================
// PAYMENT GATEWAY SERVICE (Factory + Manager)
// ============================================================================

class PaymentGatewayService {
  final Map<String, PaymentGatewayProvider> _providers = {};

  PaymentGatewayService({
    String? clickMerchantId,
    String? clickServiceId,
    String? paymeMerchantId,
    String? uzcardMerchantId,
    String? uzcardTerminalId,
    String? cardApiKey,
  }) {
    // Initialize available providers (PUBLIC IDs only)
    if (clickMerchantId != null && clickServiceId != null) {
      _providers['click'] = ClickPaymentProvider(
        merchantId: clickMerchantId,
        serviceId: clickServiceId,
      );
    }

    if (paymeMerchantId != null) {
      _providers['payme'] = PaymePaymentProvider(
        merchantId: paymeMerchantId,
      );
    }

    if (uzcardMerchantId != null && uzcardTerminalId != null) {
      _providers['uzcard'] = UzcardPaymentProvider(
        merchantId: uzcardMerchantId,
        terminalId: uzcardTerminalId,
      );
    }

    if (cardApiKey != null) {
      _providers['card'] = CardPaymentProvider(apiKey: cardApiKey);
    }
  }

  /// Get provider by name
  PaymentGatewayProvider? getProvider(String name) => _providers[name];

  /// Get available providers
  List<String> get availableProviders => _providers.keys.toList();

  /// Initialize payment with specified provider
  Future<PaymentInitResult> initializePayment({
    required String provider,
    required String orderId,
    required double amount,
    required String currency,
    required String returnUrl,
    Map<String, dynamic>? metadata,
  }) async {
    final p = _providers[provider];
    if (p == null) {
      return PaymentInitResult.failure('provider_not_configured: $provider');
    }

    return p.initializePayment(
      orderId: orderId,
      amount: amount,
      currency: currency,
      returnUrl: returnUrl,
      metadata: metadata,
    );
  }

  /// Check payment status
  Future<PaymentStatusResult> checkPaymentStatus({
    required String provider,
    required String transactionId,
  }) async {
    final p = _providers[provider];
    if (p == null) {
      return PaymentStatusResult.failure('provider_not_configured: $provider');
    }

    return p.checkPaymentStatus(transactionId);
  }
}

// ============================================================================
// PAYMENT GATEWAY CONFIG (PUBLIC IDS ONLY - NO SECRETS)
// ============================================================================
// Gateway credentials loaded via --dart-define at build time.
// Example build command:
//   flutter build windows --dart-define=CLICK_SERVICE_ID=12345 \
//     --dart-define=CLICK_MERCHANT_ID=67890 \
//     --dart-define=PAYME_MERCHANT_ID=abcdef
//
// SECRET KEYS must NEVER be in client code. They live in Supabase Edge Function:
//   supabase secrets set CLICK_SECRET_KEY=... PAYME_KEY=... \
//     --project-ref mbhjganbihamoiqmankv
// ============================================================================

class PaymentGatewayConfig {
  // Public identifiers only (safe to ship in app binary)
  static const clickServiceId = String.fromEnvironment('CLICK_SERVICE_ID', defaultValue: '');
  static const clickMerchantId = String.fromEnvironment('CLICK_MERCHANT_ID', defaultValue: '');
  static const paymeMerchantId = String.fromEnvironment('PAYME_MERCHANT_ID', defaultValue: '');
  static const uzcardMerchantId = String.fromEnvironment('UZCARD_MERCHANT_ID', defaultValue: '');
  static const uzcardTerminalId = String.fromEnvironment('UZCARD_TERMINAL_ID', defaultValue: '');
  static const cardApiKey = String.fromEnvironment('CARD_API_KEY', defaultValue: '');

  static PaymentGatewayService createService() {
    return PaymentGatewayService(
      clickMerchantId: clickMerchantId.isNotEmpty ? clickMerchantId : null,
      clickServiceId: clickServiceId.isNotEmpty ? clickServiceId : null,
      paymeMerchantId: paymeMerchantId.isNotEmpty ? paymeMerchantId : null,
      uzcardMerchantId: uzcardMerchantId.isNotEmpty ? uzcardMerchantId : null,
      uzcardTerminalId: uzcardTerminalId.isNotEmpty ? uzcardTerminalId : null,
      cardApiKey: cardApiKey.isNotEmpty ? cardApiKey : null,
    );
  }
}
