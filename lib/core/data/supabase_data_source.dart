import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';

class SupabaseDataSource {
  const SupabaseDataSource();

  SupabaseClient get client => supabase;

  GoTrueClient get auth => supabase.auth;

  SupabaseQueryBuilder table(String name) => supabase.from(name);

  StorageFileApi storageBucket(String bucket) => supabase.storage.from(bucket);

  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map<String, dynamic>? params,
    bool get = false,
  }) {
    return supabase.rpc<T>(fn, params: params, get: get);
  }

  RealtimeChannel channel(
    String name, {
    RealtimeChannelConfig opts = const RealtimeChannelConfig(),
  }) {
    return supabase.channel(name, opts: opts);
  }

  List<RealtimeChannel> getChannels() => supabase.getChannels();

  Future<void> removeChannel(RealtimeChannel channel) {
    return supabase.removeChannel(channel);
  }

  Future<void> removeAllChannels() => supabase.removeAllChannels();

  Future<FunctionResponse> invokeFunction(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
  }) {
    return supabase.functions.invoke(
      functionName,
      headers: headers,
      body: body,
      files: files,
      queryParameters: queryParameters,
      method: method,
      region: region,
    );
  }
}
