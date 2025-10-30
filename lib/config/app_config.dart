import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

/// Application configuration utility for accessing environment variables
///
/// Usage:
/// ```dart
/// final apiKey = AppConfig.geminiApiKey;
/// final supabaseUrl = AppConfig.supabaseUrl;
/// ```
class AppConfig {
  // Private constructor to prevent instantiation
  AppConfig._();

  /// Loads environment variables from assets/app.env (preferred) or .env fallback
  /// Call this in main() before runApp()
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: 'assets/app.env');
    } catch (e) {
      // Fallback to root .env if asset not found
      try {
        await dotenv.load(fileName: '.env');
      } catch (e2) {
        throw Exception(
          'Failed to load env file. Expected assets/app.env (preferred) or .env in project root.\n'
          'Create one with: GEMINI_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY.\n'
          'Errors: asset=$e, root=$e2',
        );
      }
    }
  }

  /// Google Gemini API Key
  /// Get this from: https://makersuite.google.com/app/apikey
  static String get geminiApiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception(
        'GEMINI_API_KEY not found in env. Ensure it is set in assets/app.env or .env.',
      );
    }
    return key;
  }

  /// Supabase Project URL
  /// Get this from your Supabase project settings
  static String get supabaseUrl {
    final url = dotenv.env['SUPABASE_URL'];
    if (url == null || url.isEmpty) {
      throw Exception(
        'SUPABASE_URL not found in env. Ensure it is set in assets/app.env or .env.',
      );
    }
    return url;
  }

  /// Supabase Anonymous Key
  /// Get this from your Supabase project settings
  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception(
        'SUPABASE_ANON_KEY not found in env. Ensure it is set in assets/app.env or .env.',
      );
    }
    return key;
  }

  /// Check if all required environment variables are set
  static bool validateConfig() {
    try {
      // Try to access all required variables
      geminiApiKey;
      supabaseUrl;
      supabaseAnonKey;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get environment variable with optional default value
  static String? getEnv(String key, {String? defaultValue}) {
    return dotenv.env[key] ?? defaultValue;
  }

  /// Logs configuration status only in debug builds (never in production)
  /// Never logs actual secret values.
  static void printStatus() {
    if (kDebugMode) {
      debugPrint('=== App Configuration Status ===');
      debugPrint(
        'GEMINI_API_KEY: ${geminiApiKey.isNotEmpty ? "✓ Set" : "✗ Missing"}',
      );
      debugPrint(
        'SUPABASE_URL: ${supabaseUrl.isNotEmpty ? "✓ Set" : "✗ Missing"}',
      );
      debugPrint(
        'SUPABASE_ANON_KEY: ${supabaseAnonKey.isNotEmpty ? "✓ Set" : "✗ Missing"}',
      );
      debugPrint('================================');
    }
  }
}
