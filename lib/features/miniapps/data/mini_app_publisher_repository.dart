// Publisher onboarding va domen tasdiqlash uchun repository (mobil).
//
// Web'dagi `src/features/miniapps/publishers/api.ts` bilan bir xil kontrakt.

import 'package:supabase_flutter/supabase_flutter.dart';

class MiniAppPublisher {
  const MiniAppPublisher({
    required this.id,
    required this.handle,
    required this.name,
    required this.type,
    required this.verification,
    this.logoUrl,
  });

  factory MiniAppPublisher.fromMap(Map<String, dynamic> map) {
    return MiniAppPublisher(
      id: map['id'] as String,
      handle: (map['handle'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      type: (map['type'] ?? 'individual') as String,
      verification: (map['verification'] ?? 'unverified') as String,
      logoUrl: map['logo_url'] as String?,
    );
  }

  final String id;
  final String handle;
  final String name;
  final String type;
  final String verification;
  final String? logoUrl;

  bool get isVerified =>
      verification == 'domain_verified' || verification == 'official';
}

class MiniAppPublisherDomain {
  const MiniAppPublisherDomain({
    required this.id,
    required this.domain,
    this.verificationToken,
    this.verifiedAt,
    this.checkError,
  });

  factory MiniAppPublisherDomain.fromMap(Map<String, dynamic> map) {
    return MiniAppPublisherDomain(
      id: map['id'] as String,
      domain: (map['domain'] ?? '') as String,
      verificationToken: map['verification_token'] as String?,
      verifiedAt: map['verified_at'] == null
          ? null
          : DateTime.tryParse(map['verified_at'] as String),
      checkError: map['check_error'] as String?,
    );
  }

  final String id;
  final String domain;
  final String? verificationToken;
  final DateTime? verifiedAt;
  final String? checkError;

  bool get isVerified => verifiedAt != null;
}

/// Handle qoidasi: 3-32 belgi, kichik harf, raqam va pastki chiziq.
bool isValidPublisherHandle(String handle) {
  return RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(handle);
}

/// Domen qoidasi: faqat host, protokolsiz va yo'lsiz.
String? normalizePublisherDomain(String input) {
  var value = input.trim().toLowerCase();
  value = value.replaceFirst(RegExp(r'^https?://'), '');
  value = value.replaceFirst(RegExp(r'/.*$'), '');
  if (!RegExp(r'^[a-z0-9.-]+\.[a-z]{2,}$').hasMatch(value)) return null;
  return value.replaceFirst(RegExp(r'^www\.'), '');
}

class MiniAppPublisherRepository {
  MiniAppPublisherRepository(this._client);

  final SupabaseClient _client;

  Future<List<MiniAppPublisher>> listMyPublishers() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <MiniAppPublisher>[];

    final rows = await _client
        .from('publisher_members')
        .select(
          'publisher:mini_app_publishers(id, handle, name, type, verification, logo_url)',
        )
        .eq('user_id', userId);

    return (rows as List<dynamic>)
        .map((row) => (row as Map<String, dynamic>)['publisher'])
        .whereType<Map<String, dynamic>>()
        .map(MiniAppPublisher.fromMap)
        .toList(growable: false);
  }

  Future<List<MiniAppPublisherDomain>> listDomains(String publisherId) async {
    final rows = await _client
        .from('publisher_domains')
        .select('id, domain, verification_token, verified_at, check_error')
        .eq('publisher_id', publisherId);

    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(MiniAppPublisherDomain.fromMap)
        .toList(growable: false);
  }

  Future<String> createPublisher({
    required String handle,
    required String name,
    required String type,
  }) async {
    final result = await _client.rpc<dynamic>(
      'mini_app_publisher_create',
      params: <String, dynamic>{
        'p_handle': handle,
        'p_name': name,
        'p_type': type,
      },
    );
    return result.toString();
  }

  /// TXT tokenini qaytaradi.
  Future<MiniAppPublisherDomain> addDomain({
    required String publisherId,
    required String domain,
  }) async {
    final result = await _client.rpc<dynamic>(
      'mini_app_publisher_add_domain',
      params: <String, dynamic>{
        'p_publisher_id': publisherId,
        'p_domain': domain,
      },
    );
    final row = result is List ? result.first : result;
    final map = (row as Map).cast<String, dynamic>();
    return MiniAppPublisherDomain(
      id: (map['domain_id'] ?? map['id']).toString(),
      domain: domain,
      verificationToken: map['verification_token'] as String?,
    );
  }

  /// DNS TXT tekshiruvini ishga tushiradi.
  Future<bool> verifyDomain(String domainId) async {
    final response = await _client.functions.invoke(
      'mini-app-verify-domain',
      body: <String, dynamic>{'domainId': domainId},
    );
    final data = response.data;
    if (data is Map && data['verified'] == true) return true;
    return false;
  }
}
