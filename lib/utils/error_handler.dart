import 'package:flutter/material.dart';
import 'dart:async';

/// Centralized error handling utility for the application
class ErrorHandler {
  /// Shows a user-friendly error message in a SnackBar
  static void showError(BuildContext context, String message, {String? details}) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (details != null) ...[
              const SizedBox(height: 4),
              Text(
                details,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Shows a success message in a SnackBar
  static void showSuccess(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Shows a warning message in a SnackBar
  static void showWarning(BuildContext context, String message) {
    if (!context.mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Wraps an async operation with error handling
  static Future<T?> handleAsync<T>({
    required Future<T> Function() operation,
    required BuildContext context,
    String? errorMessage,
    bool showLoading = false,
    VoidCallback? onError,
  }) async {
    try {
      return await operation();
    } on TimeoutException {
      if (context.mounted) {
        showError(
          context,
          errorMessage ?? 'Operation timed out',
          details: 'The request took too long to complete. Please try again.',
        );
      }
      onError?.call();
      return null;
    } catch (e) {
      if (context.mounted) {
        showError(
          context,
          errorMessage ?? 'An error occurred',
          details: e.toString(),
        );
      }
      onError?.call();
      return null;
    }
  }

  /// Formats exception messages for user display
  static String formatErrorMessage(dynamic error) {
    if (error == null) return 'Unknown error occurred';
    
    final errorStr = error.toString();
    
    // Network errors
    if (errorStr.contains('SocketException') || errorStr.contains('ClientException')) {
      return 'Network error. Please check your internet connection.';
    }
    
    // Timeout errors
    if (errorStr.contains('TimeoutException')) {
      return 'Request timed out. Please try again.';
    }
    
    // Format exception
    if (errorStr.contains('FormatException')) {
      return 'Data format error. The response was invalid.';
    }
    
    // HTTP errors
    if (errorStr.contains('403')) {
      return 'Access denied. You do not have permission.';
    }
    if (errorStr.contains('404')) {
      return 'Resource not found.';
    }
    if (errorStr.contains('429')) {
      return 'Too many requests. Please wait a moment.';
    }
    if (errorStr.contains('500') || errorStr.contains('503')) {
      return 'Server error. Please try again later.';
    }
    
    // Supabase errors
    if (errorStr.contains('AuthException')) {
      return 'Authentication error. Please try logging in again.';
    }
    if (errorStr.contains('StorageException')) {
      return 'Storage error. Could not access files.';
    }
    
    // PDF errors
    if (errorStr.contains('PdfException')) {
      return 'PDF error. The file may be corrupted or unsupported.';
    }
    
    // Default
    return errorStr.length > 100 ? '${errorStr.substring(0, 97)}...' : errorStr;
  }

  /// Validates file size (in bytes)
  static bool validateFileSize(int bytes, {int maxMB = 50}) {
    return bytes <= (maxMB * 1024 * 1024);
  }

  /// Validates text input
  static String? validateInput(String? value, {
    required String fieldName,
    int? minLength,
    int? maxLength,
    bool required = true,
  }) {
    if (required && (value == null || value.trim().isEmpty)) {
      return '$fieldName is required';
    }
    
    if (value != null && minLength != null && value.length < minLength) {
      return '$fieldName must be at least $minLength characters';
    }
    
    if (value != null && maxLength != null && value.length > maxLength) {
      return '$fieldName must not exceed $maxLength characters';
    }
    
    return null;
  }
}

/// Extension for safe async operations with timeout
extension SafeAsync<T> on Future<T> {
  /// Adds a timeout to the future with a default value on timeout
  Future<T> withTimeout(Duration duration, {T? onTimeout}) {
    return timeout(
      duration,
      onTimeout: onTimeout != null ? () => onTimeout : null,
    );
  }
}

