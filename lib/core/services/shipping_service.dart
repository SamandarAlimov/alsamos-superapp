// Shipping service with delivery estimation and carrier integration
// Supports multiple carriers (placeholder for CDEK, Pochta, etc.)

import 'dart:math';

/// Shipping carrier provider interface
abstract class ShippingCarrier {
  String get name;
  
  /// Calculate shipping cost
  Future<ShippingCostResult> calculateCost({
    required String fromCity,
    required String toCity,
    required double weight, // kg
    required double declaredValue,
  });
  
  /// Estimate delivery time
  Future<DeliveryEstimate> estimateDelivery({
    required String fromCity,
    required String toCity,
    required String serviceType, // standard, express, etc.
  });
  
  /// Create shipment and get tracking number
  Future<ShipmentResult> createShipment({
    required String orderId,
    required ShippingAddress from,
    required ShippingAddress to,
    required double weight,
    required double declaredValue,
    required String serviceType,
  });
  
  /// Track shipment status
  Future<TrackingResult> trackShipment(String trackingNumber);
}

/// Shipping cost result
class ShippingCostResult {
  final bool success;
  final String? error;
  final double cost;
  final String currency;
  final Map<String, dynamic>? breakdown; // Optional cost breakdown

  const ShippingCostResult({
    required this.success,
    this.error,
    required this.cost,
    required this.currency,
    this.breakdown,
  });

  factory ShippingCostResult.success({
    required double cost,
    required String currency,
    Map<String, dynamic>? breakdown,
  }) =>
      ShippingCostResult(
        success: true,
        cost: cost,
        currency: currency,
        breakdown: breakdown,
      );

  factory ShippingCostResult.failure(String error) => ShippingCostResult(
        success: false,
        error: error,
        cost: 0,
        currency: 'UZS',
      );
}

/// Delivery time estimate
class DeliveryEstimate {
  final bool success;
  final String? error;
  final int minDays;
  final int maxDays;
  final DateTime? estimatedDate;

  const DeliveryEstimate({
    required this.success,
    this.error,
    required this.minDays,
    required this.maxDays,
    this.estimatedDate,
  });

  factory DeliveryEstimate.success({
    required int minDays,
    required int maxDays,
    DateTime? estimatedDate,
  }) =>
      DeliveryEstimate(
        success: true,
        minDays: minDays,
        maxDays: maxDays,
        estimatedDate: estimatedDate,
      );

  factory DeliveryEstimate.failure(String error) => DeliveryEstimate(
        success: false,
        error: error,
        minDays: 0,
        maxDays: 0,
      );

  String get rangeText => '$minDays-$maxDays kun';
}

/// Shipment creation result
class ShipmentResult {
  final bool success;
  final String? error;
  final String? trackingNumber;
  final String? labelUrl; // URL to shipping label PDF

  const ShipmentResult({
    required this.success,
    this.error,
    this.trackingNumber,
    this.labelUrl,
  });

  factory ShipmentResult.success({
    required String trackingNumber,
    String? labelUrl,
  }) =>
      ShipmentResult(
        success: true,
        trackingNumber: trackingNumber,
        labelUrl: labelUrl,
      );

  factory ShipmentResult.failure(String error) => ShipmentResult(
        success: false,
        error: error,
      );
}

/// Shipment tracking result
class TrackingResult {
  final bool success;
  final String? error;
  final String status; // in_transit, delivered, exception, etc.
  final String? location;
  final DateTime? lastUpdate;
  final List<TrackingEvent> events;

  const TrackingResult({
    required this.success,
    this.error,
    required this.status,
    this.location,
    this.lastUpdate,
    this.events = const [],
  });

  factory TrackingResult.success({
    required String status,
    String? location,
    DateTime? lastUpdate,
    List<TrackingEvent> events = const [],
  }) =>
      TrackingResult(
        success: true,
        status: status,
        location: location,
        lastUpdate: lastUpdate,
        events: events,
      );

  factory TrackingResult.failure(String error) => TrackingResult(
        success: false,
        error: error,
        status: 'unknown',
      );
}

class TrackingEvent {
  final String status;
  final String? location;
  final String? description;
  final DateTime timestamp;

  const TrackingEvent({
    required this.status,
    this.location,
    this.description,
    required this.timestamp,
  });
}

class ShippingAddress {
  final String fullName;
  final String phone;
  final String street;
  final String city;
  final String region;
  final String zip;
  final String? country;

  const ShippingAddress({
    required this.fullName,
    required this.phone,
    required this.street,
    required this.city,
    required this.region,
    required this.zip,
    this.country = 'UZ',
  });
}

// ============================================================================
// PLACEHOLDER CARRIER (for development without real API keys)
// ============================================================================

class PlaceholderCarrier implements ShippingCarrier {
  @override
  String get name => 'placeholder';

  @override
  Future<ShippingCostResult> calculateCost({
    required String fromCity,
    required String toCity,
    required double weight,
    required double declaredValue,
  }) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Simple distance-based calculation
    final distance = _calculateDistance(fromCity, toCity);
    const baseCost = 15000.0; // Base cost in UZS
    final distanceCost = distance * 100; // 100 UZS per km
    final weightCost = weight * 5000; // 5000 UZS per kg
    final total = baseCost + distanceCost + weightCost;

    return ShippingCostResult.success(
      cost: total,
      currency: 'UZS',
      breakdown: {
        'base': baseCost,
        'distance': distanceCost,
        'weight': weightCost,
      },
    );
  }

  @override
  Future<DeliveryEstimate> estimateDelivery({
    required String fromCity,
    required String toCity,
    required String serviceType,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final distance = _calculateDistance(fromCity, toCity);
    int minDays, maxDays;

    if (serviceType == 'express') {
      minDays = (distance / 200).ceil().clamp(1, 3);
      maxDays = minDays + 1;
    } else {
      minDays = (distance / 100).ceil().clamp(2, 7);
      maxDays = minDays + 3;
    }

    final estimatedDate = DateTime.now().add(Duration(days: maxDays));

    return DeliveryEstimate.success(
      minDays: minDays,
      maxDays: maxDays,
      estimatedDate: estimatedDate,
    );
  }

  @override
  Future<ShipmentResult> createShipment({
    required String orderId,
    required ShippingAddress from,
    required ShippingAddress to,
    required double weight,
    required double declaredValue,
    required String serviceType,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    // Generate mock tracking number
    final trackingNumber = 'TRK${orderId.substring(0, 10).toUpperCase()}';

    return ShipmentResult.success(
      trackingNumber: trackingNumber,
      labelUrl: null, // No label in placeholder
    );
  }

  @override
  Future<TrackingResult> trackShipment(String trackingNumber) async {
    await Future.delayed(const Duration(milliseconds: 400));

    // Mock tracking data
    final now = DateTime.now();
    return TrackingResult.success(
      status: 'in_transit',
      location: 'Toshkent',
      lastUpdate: now,
      events: [
        TrackingEvent(
          status: 'picked_up',
          location: 'Toshkent',
          description: 'Jo\'natma qabul qilindi',
          timestamp: now.subtract(const Duration(hours: 12)),
        ),
        TrackingEvent(
          status: 'in_transit',
          location: 'Toshkent',
          description: 'Yetkazish markazida',
          timestamp: now.subtract(const Duration(hours: 6)),
        ),
      ],
    );
  }

  double _calculateDistance(String fromCity, String toCity) {
    // Mock distance calculation
    final random = Random(fromCity.hashCode + toCity.hashCode);
    return 50 + random.nextDouble() * 500; // 50-550 km
  }
}

// ============================================================================
// SHIPPING SERVICE (manages carriers)
// ============================================================================

class ShippingService {
  final Map<String, ShippingCarrier> _carriers = {};

  ShippingService({
    String? cdekApiKey,
    String? pochtaApiKey,
  }) {
    // Register carriers based on available API keys
    if (cdekApiKey != null && cdekApiKey.isNotEmpty) {
      // _carriers['cdek'] = CDEKCarrier(apiKey: cdekApiKey);
    }
    if (pochtaApiKey != null && pochtaApiKey.isNotEmpty) {
      // _carriers['pochta'] = PochtaCarrier(apiKey: pochtaApiKey);
    }

    // Always add placeholder for development
    _carriers['placeholder'] = PlaceholderCarrier();
  }

  ShippingCarrier? getCarrier(String name) => _carriers[name];
  
  List<String> get availableCarriers => _carriers.keys.toList();

  /// Calculate shipping cost with best available carrier
  Future<ShippingCostResult> calculateCost({
    required String fromCity,
    required String toCity,
    required double weight,
    required double declaredValue,
    String? preferredCarrier,
  }) async {
    final carrier = preferredCarrier != null
        ? _carriers[preferredCarrier]
        : _carriers.values.firstOrNull;

    if (carrier == null) {
      return ShippingCostResult.failure('No carrier available');
    }

    return carrier.calculateCost(
      fromCity: fromCity,
      toCity: toCity,
      weight: weight,
      declaredValue: declaredValue,
    );
  }

  /// Estimate delivery time
  Future<DeliveryEstimate> estimateDelivery({
    required String fromCity,
    required String toCity,
    String serviceType = 'standard',
    String? preferredCarrier,
  }) async {
    final carrier = preferredCarrier != null
        ? _carriers[preferredCarrier]
        : _carriers.values.firstOrNull;

    if (carrier == null) {
      return DeliveryEstimate.failure('No carrier available');
    }

    return carrier.estimateDelivery(
      fromCity: fromCity,
      toCity: toCity,
      serviceType: serviceType,
    );
  }
}

// ============================================================================
// SERVICE FACTORY
// ============================================================================

class ShippingServiceConfig {
  static ShippingService createService() {
    return ShippingService(
      cdekApiKey: const String.fromEnvironment('CDEK_API_KEY'),
      pochtaApiKey: const String.fromEnvironment('POCHTA_API_KEY'),
    );
  }
}
