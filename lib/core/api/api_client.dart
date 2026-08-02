import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'endpoints.dart';

/// Erreur applicative remontée par l'API.
///
/// Étend [DioException] afin de pouvoir être propagée telle quelle par la
/// chaîne d'intercepteurs de Dio, tout en restant interceptable via
/// `on ApiException catch (e)` par les couches supérieures.
class ApiException extends DioException {
  /// Message lisible par l'utilisateur (toujours renseigné).
  final String messageApi;
  final int? statusCode;
  final Map<String, dynamic>? responseData;

  ApiException(
    this.messageApi, {
    this.statusCode,
    this.responseData,
    required super.requestOptions,
    super.response,
    super.type,
    super.error,
    super.stackTrace,
  });

  @override
  String get message => messageApi;

  @override
  String toString() => 'ApiException($statusCode): $messageApi';
}

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  static const _tokenKey = 'session_token';

  /// Appelé quand le serveur n'accepte plus le jeton.
  ///
  /// [motif] porte l'explication du serveur quand il en donne une — un appareil
  /// retiré des appareils de confiance, notamment. Sans elle, l'application
  /// annonce « session expirée » là où c'est une décision prise contre son
  /// porteur, et il signale une panne au lieu de comprendre.
  void Function(String? motif)? onUnauthorized;

  ApiClient({required FlutterSecureStorage secureStorage})
      : _secureStorage = secureStorage {
    _dio = Dio(BaseOptions(
      baseUrl: kApiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'apikey': kSupabaseAnonKey,
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _secureStorage.read(key: _tokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        // Un 401 ne vaut expiration de session que s'il vient d'une route de
        // données. Sur `/auth/login` et `/auth/unlock`, il signifie simplement
        // « mauvais mot de passe » : le signaler comme une expiration
        // déconnectait l'utilisateur au premier code mal tapé.
        final chemin = error.requestOptions.path;
        String message = 'Erreur réseau';
        Map<String, dynamic>? responseData;
        final data = error.response?.data;
        if (data is Map) {
          responseData = Map<String, dynamic>.from(data);
          final erreur = responseData['error'];
          if (erreur is String && erreur.isNotEmpty) message = erreur;
        } else if (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout) {
          message = 'Délai de connexion dépassé';
        } else if (error.type == DioExceptionType.connectionError) {
          message = 'Impossible de se connecter au serveur';
        }
        if (error.response?.statusCode == 401 && !chemin.startsWith('/auth/')) {
          // Le serveur nomme le motif quand il en a un : on le transmet tel
          // quel plutôt que d'inventer une explication.
          final retire = responseData?['appareilRetire'] == true;
          onUnauthorized?.call(retire ? message : null);
        }
        handler.next(ApiException(
          message,
          statusCode: error.response?.statusCode,
          responseData: responseData,
          requestOptions: error.requestOptions,
          response: error.response,
          type: error.type,
          error: error.error,
          stackTrace: error.stackTrace,
        ));
      },
    ));
  }

  Future<void> setSessionToken(String? token) async {
    if (token == null) {
      await _secureStorage.delete(key: _tokenKey);
    } else {
      await _secureStorage.write(key: _tokenKey, value: token);
    }
  }

  Future<bool> sante() async {
    try {
      final response = await _dio.get(kHealth);
      return response.statusCode == 200 && response.data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Dio get dio => _dio;
}
