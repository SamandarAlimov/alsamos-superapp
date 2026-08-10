import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide Message;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/supabase/supabase_client.dart';
import '../../../../firebase_options.dart';
import '../local/messages_local_store.dart';
import '../models/message_interaction_model.dart';
import '../models/message_model.dart';

const _replyActionId = 'alsamos_reply';
const _markReadActionId = 'alsamos_mark_read';

@pragma('vm:entry-point')
Future<void> alsamosFirebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  if (!MessageNotificationsService.isMessagingSupported) return;
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      // Background Firebase init failed - silent skip
      return;
    }
  }
  await MessageNotificationsService.handleBackgroundMessage(message);
}

class MessageNotificationsService {
  MessageNotificationsService._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool get isMessagingSupported {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };
  }

  static Future<void> init() async {
    if (!isMessagingSupported) {
      // Push notifications not supported on this platform - silent skip
      return;
    }
    if (Firebase.apps.isEmpty) {
      // Firebase not initialized - silent skip
      return;
    }
    try {
      FirebaseMessaging.onBackgroundMessage(
          alsamosFirebaseMessagingBackgroundHandler);
      await _local.initialize(
        InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            notificationCategories: [
              DarwinNotificationCategory(
                'alsamos_message',
                actions: [
                  DarwinNotificationAction.text(
                    _replyActionId,
                    'Reply',
                    buttonTitle: 'Send',
                    placeholder: 'Message',
                  ),
                  DarwinNotificationAction.plain(
                    _markReadActionId,
                    'Mark as read',
                  ),
                ],
              ),
            ],
          ),
        ),
        onDidReceiveNotificationResponse: handleNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: handleNotificationResponse,
      );
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      await _syncPushToken(token);
      FirebaseMessaging.instance.onTokenRefresh.listen(_syncPushToken);
      FirebaseMessaging.onMessage.listen(showForegroundNotification);
      FirebaseMessaging.onMessageOpenedApp.listen(handleOpenedMessage);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) await handleOpenedMessage(initial);
    } catch (e) {
      // Notification initialization failed - continue without push
      if (kDebugMode) {
        debugPrint('[Notifications] Initialization failed: $e');
      }
    }
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    final data = message.data;
    final conversationId = data['conversation_id'];
    if (conversationId is! String || conversationId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList('alsamos_pending_pushes') ?? const [];
    await prefs.setStringList('alsamos_pending_pushes', [
      ...pending,
      jsonEncode(data),
    ]);
  }

  static Future<void> showForegroundNotification(RemoteMessage message) async {
    final data = message.data;
    final conversationId = data['conversation_id']?.toString();
    if (conversationId == null) return;
    await _local.show(
      conversationId.hashCode,
      message.notification?.title ?? data['title']?.toString() ?? 'Alsamos',
      message.notification?.body ?? data['body']?.toString() ?? 'New message',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'alsamos_messages',
          'Messages',
          channelDescription: 'Alsamos message notifications',
          category: AndroidNotificationCategory.message,
          actions: const [
            AndroidNotificationAction(
              _replyActionId,
              'Reply',
              inputs: [AndroidNotificationActionInput(label: 'Message')],
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              _markReadActionId,
              'Mark as read',
              showsUserInterface: false,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
            categoryIdentifier: 'alsamos_message'),
      ),
      payload: jsonEncode(data),
    );
  }

  static Future<void> handleOpenedMessage(RemoteMessage message) async {
    await handleBackgroundMessage(message);
  }

  @pragma('vm:entry-point')
  static Future<void> handleNotificationResponse(
      NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    final conversationId = data['conversation_id']?.toString();
    final userId = supabase.auth.currentUser?.id;
    if (conversationId == null || userId == null) return;
    if (response.actionId == _replyActionId) {
      final text = response.input?.trim();
      if (text != null && text.isNotEmpty) {
        final temp = Message(
          id: 'temp-${DateTime.now().microsecondsSinceEpoch}',
          conversationId: conversationId,
          senderId: userId,
          content: text,
          createdAt: DateTime.now(),
          status: 'sending',
        );
        await MessagesLocalStore.instance.upsertMessage(temp);
        await MessagesLocalStore.instance.enqueue(temp);
      }
    } else if (response.actionId == _markReadActionId) {
      await MessagesLocalStore.instance.enqueueInteraction(
        MessageInteractionOutboxItem(
          localId: 'ix-${DateTime.now().microsecondsSinceEpoch}',
          type: 'mark_read',
          conversationId: conversationId,
          payload: const {},
          createdAt: DateTime.now(),
          nextRetryAt: DateTime.now(),
        ),
      );
    }
    await _local.cancel(conversationId.hashCode);
  }

  static Future<void> _syncPushToken(String? token) async {
    final uid = supabase.auth.currentUser?.id;
    if (token == null || uid == null) return;
    await supabase.from('user_push_tokens').upsert({
      'user_id': uid,
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'token');
  }
}
