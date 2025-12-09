import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/presentation/home_tab_provider.dart';
import 'push_navigation_intent.dart';

class PushNotificationHandler {
  PushNotificationHandler(this._ref);

  final Ref _ref;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleMessage(initialMessage);
    }

    _openedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
  }

  void _handleMessage(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;

    final event = data['event']?.toString().trim();
    if (event == null || event.isEmpty) return;

    switch (event) {
      case 'queue_status_update':
      case 'boat_launch_request':
        _ref.read(pushNavigationIntentProvider.notifier).state =
            PushNavigationIntent.queueStatus(
              queueEntryId: data['queue_entry_id']?.toString() ??
                  data['entry_id']?.toString() ??
                  '',
              marinaId: data['marina_id']?.toString(),
              boatId: data['boat_id']?.toString(),
            );
        _ref.read(homeTabIndexProvider.notifier).state = homeTabQueueIndex;
        break;
      case 'marina_wall_post':
        final postId = data['post_id']?.toString() ?? '';
        if (postId.isEmpty) return;
        _ref.read(pushNavigationIntentProvider.notifier).state =
            PushNavigationIntent.muralPost(
              postId: postId,
              marinaId: data['marina_id']?.toString(),
            );
        _ref.read(homeTabIndexProvider.notifier).state = homeTabMuralIndex;
        break;
      default:
        break;
    }
  }

  Future<void> dispose() async {
    await _openedSubscription?.cancel();
  }
}

final pushNotificationHandlerProvider =
    Provider<PushNotificationHandler>((ref) {
  final handler = PushNotificationHandler(ref);
  ref.onDispose(() {
    handler.dispose();
  });
  unawaited(handler.initialize());
  return handler;
});
