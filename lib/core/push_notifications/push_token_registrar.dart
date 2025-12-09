import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase_providers.dart';

final pushTokenRegistrarProvider = Provider<PushTokenRegistrar>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final registrar = PushTokenRegistrar(client);
  ref.onDispose(() {
    unawaited(registrar.dispose());
  });
  return registrar;
});

class PushTokenRegistrar {
  PushTokenRegistrar(this._client);

  final SupabaseClient _client;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _currentUserId;

  static const _devicePrefsKey = 'push_device_identifier_v1';

  Future<void> handleSession(Session? session) async {
    if (!_supportsPush) return;

    final user = session?.user;
    if (user == null) {
      await _cleanupCurrentToken();
      return;
    }

    if (_currentUserId != user.id) {
      _currentUserId = user.id;
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription =
          FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) => _persistToken(userId: user.id, token: token),
        onError: (error, _) {
          debugPrint('Falha ao atualizar token de push: $error');
        },
      );
    }

    await _ensurePermissionAndSync(user.id);
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool get _supportsPush => _isAndroid || _isIOS;

  Future<void> _ensurePermissionAndSync(String userId) async {
    final granted = await _requestPermission();
    if (!granted) return;

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } on FirebaseException catch (error) {
      if (error.code == 'apns-token-not-set') {
        debugPrint(
          'APNS token indisponível no momento; pulando registro de push.',
        );
        return;
      }
      debugPrint('Erro ao obter token do Firebase Messaging: $error');
      return;
    } catch (error) {
      debugPrint('Erro ao obter token do Firebase Messaging: $error');
      return;
    }

    if (token == null || token.isEmpty) {
      debugPrint('Firebase Messaging não retornou token.');
      return;
    }

    await _persistToken(userId: userId, token: token);
  }

  Future<bool> _requestPermission() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.setAutoInitEnabled(true);
      if (_isIOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        carPlay: false,
        provisional: true,
      );

      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (error) {
      debugPrint('Erro ao solicitar permissão de notificações: $error');
      return false;
    }
  }

  Future<void> _persistToken({
    required String userId,
    required String token,
  }) async {
    if (token.isEmpty) return;

    final deviceId = await _getOrCreateDeviceId();
    final platform = _isIOS ? 'ios' : 'android';

    try {
      await _client.from('user_push_tokens').upsert(
        <String, dynamic>{
          'user_id': userId,
          'device_id': deviceId,
          'token': token,
          'platform': platform,
        },
        onConflict: 'user_id,device_id',
      );
    } catch (error) {
      debugPrint('Erro ao salvar token no Supabase: $error');
    }
  }

  Future<void> _cleanupCurrentToken() async {
    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = null;

    final userId = _currentUserId;
    _currentUserId = null;
    if (userId == null) return;

    final deviceId = await _getStoredDeviceId();
    if (deviceId == null) return;

    try {
      await _client
          .from('user_push_tokens')
          .delete()
          .match({'user_id': userId, 'device_id': deviceId});
    } catch (error) {
      debugPrint('Erro ao remover token no logout: $error');
    }
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_devicePrefsKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final newId = const Uuid().v4();
    await prefs.setString(_devicePrefsKey, newId);
    return newId;
  }

  Future<String?> _getStoredDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_devicePrefsKey);
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
  }
}
