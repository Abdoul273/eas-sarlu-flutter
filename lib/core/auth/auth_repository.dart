import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';

class UnlockException implements Exception {
  final String message;
  final int essaisRestants;
  final bool bloque;

  UnlockException(
      {required this.message, this.essaisRestants = 0, this.bloque = false});

  @override
  String toString() => 'UnlockException: $message';
}

class AuthRepository {
  final ApiClient _apiClient;
  final FlutterSecureStorage _secureStorage;
  static const _deviceIdKey = 'device_secret';
  static const _deviceNomKey = 'device_nom';

  AuthRepository({
    required ApiClient apiClient,
    required FlutterSecureStorage secureStorage,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

  Future<String> getOrCreateDeviceId(String? serverDeviceId) async {
    final existing = await _secureStorage.read(key: _deviceIdKey);
    if (existing != null) return existing;
    final newId = serverDeviceId ?? '';
    if (newId.isNotEmpty) {
      await _secureStorage.write(key: _deviceIdKey, value: newId);
    }
    return newId;
  }

  Future<String?> getDeviceId() => _secureStorage.read(key: _deviceIdKey);

  Future<void> setDeviceNom(String nom) async {
    await _secureStorage.write(key: _deviceNomKey, value: nom);
  }

  Future<String> getDeviceNom() async {
    return await _secureStorage.read(key: _deviceNomKey) ?? 'Appareil';
  }

  Future<Map<String, dynamic>> login(String email, String password,
      {String? deviceNom}) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'deviceId': await getDeviceId() ?? '',
      'deviceNom': deviceNom ?? await getDeviceNom(),
    };
    final response = await _apiClient.dio.post(kAuthLogin, data: body);
    final data = response.data as Map<String, dynamic>;
    final deviceId = data['deviceId'] as String;
    await _secureStorage.write(key: _deviceIdKey, value: deviceId);
    final token = data['token'] as String;
    await _apiClient.setSessionToken(token);
    return data;
  }

  Future<Map<String, dynamic>> unlock(
      String deviceId, String userId, String code) async {
    try {
      final response = await _apiClient.dio.post(kAuthUnlock, data: {
        'deviceId': deviceId,
        'userId': userId,
        'code': code,
      });
      final data = response.data as Map<String, dynamic>;
      final token = data['token'] as String;
      await _apiClient.setSessionToken(token);
      return data;
    } on ApiException catch (e) {
      final data = e.responseData;
      if (data != null && e.statusCode == 401) {
        final essais = data['essaisRestants'] as int? ?? 0;
        final bloque = data['bloque'] as bool? ?? false;
        throw UnlockException(
          message: e.message,
          essaisRestants: essais,
          bloque: bloque,
        );
      }
      rethrow;
    }
  }

  Future<void> setCode(String deviceId, String code) async {
    await _apiClient.dio.post(kAuthSetCode, data: {
      'deviceId': deviceId,
      'code': code,
    });
  }

  Future<Map<String, dynamic>?> getDeviceInfo(String deviceId) async {
    try {
      final response = await _apiClient.dio.get('$kAuthDevice$deviceId');
      return response.data as Map<String, dynamic>;
    } on ApiException {
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _apiClient.dio.post(kAuthLogout);
    } catch (_) {}
    await _apiClient.setSessionToken(null);
  }

  Future<Map<String, dynamic>?> me() async {
    try {
      final response = await _apiClient.dio.get(kAuthMe);
      return response.data as Map<String, dynamic>;
    } on ApiException {
      return null;
    }
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    await _apiClient.dio.post(kAuthChangePassword, data: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }
}
