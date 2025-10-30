# Quick Reference - Error Handling

## 🚀 Quick Start

### Import the Error Handler
```dart
import '../utils/error_handler.dart';
```

---

## 📋 Common Patterns

### 1. Show Error Message
```dart
ErrorHandler.showError(
  context,
  'Operation failed',
  details: 'Detailed error message',
);
```

### 2. Show Success Message
```dart
ErrorHandler.showSuccess(
  context,
  'File uploaded successfully!',
);
```

### 3. Show Warning
```dart
ErrorHandler.showWarning(
  context,
  'File is quite large, processing may take a while',
);
```

---

## 🔍 Validation

### Validate Text Input
```dart
final error = ErrorHandler.validateInput(
  textController.text,
  fieldName: 'Context',
  minLength: 3,
  maxLength: 500,
  required: true,
);

if (error != null) {
  ErrorHandler.showError(context, error);
  return;
}
```

### Validate File Size
```dart
if (!ErrorHandler.validateFileSize(bytes.length, maxMB: 50)) {
  ErrorHandler.showError(
    context,
    'File too large',
    details: 'Maximum size is 50MB',
  );
  return;
}
```

---

## ⏱️ Timeout Handling

### Add Timeout to HTTP Request
```dart
final response = await http
    .post(uri, headers: headers, body: body)
    .timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException('Request timed out'),
    );
```

### Catch Timeout Exception
```dart
try {
  // Your async operation
} on TimeoutException {
  ErrorHandler.showError(
    context,
    'Operation timed out',
    details: 'Please try again',
  );
} catch (e) {
  ErrorHandler.showError(
    context,
    'Operation failed',
    details: ErrorHandler.formatErrorMessage(e),
  );
}
```

---

## 🎨 Error Formatting

### Format Exception for User Display
```dart
try {
  // Your code
} catch (e) {
  final userMessage = ErrorHandler.formatErrorMessage(e);
  ErrorHandler.showError(context, userMessage);
}
```

**Handles:**
- Network errors → "Network error. Please check your internet connection."
- Timeout errors → "Request timed out. Please try again."
- HTTP 403 → "Access denied. You do not have permission."
- HTTP 404 → "Resource not found."
- HTTP 429 → "Too many requests. Please wait a moment."
- HTTP 500/503 → "Server error. Please try again later."
- Supabase errors → "Authentication/Storage error..."
- PDF errors → "PDF error. The file may be corrupted..."

---

## 🛡️ Safe Async Operations

### Wrap Async with Error Handling
```dart
final result = await ErrorHandler.handleAsync<String>(
  operation: () => fetchDataFromApi(),
  context: context,
  errorMessage: 'Failed to fetch data',
  onError: () {
    // Optional cleanup
  },
);

if (result != null) {
  // Use result
}
```

---

## ✅ Mounted Check Pattern

### Always Check Before setState
```dart
try {
  final data = await fetchData();
  if (!mounted) return;
  setState(() => _data = data);
} catch (e) {
  if (!mounted) return;
  ErrorHandler.showError(context, 'Failed to load');
}
```

---

## 📱 File Picker Pattern

### Safe File Selection
```dart
try {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    withData: true,
  );
  
  if (result == null || result.files.isEmpty) return;
  
  final picked = result.files.first;
  
  if (picked.bytes == null) {
    throw Exception('Failed to read file data');
  }
  
  if (!ErrorHandler.validateFileSize(picked.bytes!.length, maxMB: 50)) {
    throw Exception('File size must not exceed 50MB');
  }
  
  // Process file
} catch (e) {
  ErrorHandler.showError(
    context,
    'File selection failed',
    details: ErrorHandler.formatErrorMessage(e),
  );
}
```

---

## 🔄 Retry Pattern

### Error Screen with Retry
```dart
Widget _buildErrorState(String error) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text('Failed to load', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
            ),
          ],
        ),
      ],
    ),
  );
}
```

---

## 🎯 Loading State Pattern

### Show Loading Indicator
```dart
Widget _buildBody() {
  if (_loading) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading...'),
        ],
      ),
    );
  }
  
  if (_error != null) {
    return _buildErrorState(_error!);
  }
  
  return _buildContent();
}
```

---

## 🔐 Route Argument Validation

### Safe Route Arguments
```dart
'/myRoute': (context) {
  final args = ModalRoute.of(context)?.settings.arguments as Map?;
  final data = args?['data'] as MyType?;
  
  if (data == null) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Invalid data'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
  
  return MyScreen(data: data);
},
```

---

## 📊 API Call Pattern

### Complete API Call with Error Handling
```dart
Future<void> _callApi() async {
  if (_loading) return;
  
  setState(() {
    _loading = true;
    _error = null;
  });
  
  try {
    final uri = Uri.parse('https://api.example.com/endpoint');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'data': 'value'}),
        )
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw TimeoutException('Request timed out'),
        );
    
    if (response.statusCode != 200) {
      throw Exception('API error (${response.statusCode}): ${response.body}');
    }
    
    final data = jsonDecode(response.body);
    
    if (!mounted) return;
    
    setState(() {
      _result = data;
      _loading = false;
    });
    
    ErrorHandler.showSuccess(context, 'Operation completed!');
    
  } on TimeoutException {
    if (!mounted) return;
    setState(() {
      _error = 'Request timed out';
      _loading = false;
    });
    ErrorHandler.showError(
      context,
      'Timeout',
      details: 'The request took too long',
    );
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _error = ErrorHandler.formatErrorMessage(e);
      _loading = false;
    });
    ErrorHandler.showError(
      context,
      'Operation failed',
      details: _error,
    );
  }
}
```

---

## 🧪 Debug Logging

### Use debugPrint for Logs
```dart
debugPrint('API request sent: $uri');
debugPrint('Response status: ${response.statusCode}');
debugPrint('Error occurred: $e');
```

**Note:** `debugPrint` automatically only logs in debug mode.

---

## 📝 Cheat Sheet

| Task | Method |
|------|--------|
| Show error | `ErrorHandler.showError(context, message, details: details)` |
| Show success | `ErrorHandler.showSuccess(context, message)` |
| Show warning | `ErrorHandler.showWarning(context, message)` |
| Validate input | `ErrorHandler.validateInput(value, fieldName: name, ...)` |
| Validate file | `ErrorHandler.validateFileSize(bytes, maxMB: 50)` |
| Format error | `ErrorHandler.formatErrorMessage(exception)` |
| Add timeout | `.timeout(Duration(...), onTimeout: () => throw ...)` |
| Check mounted | `if (!mounted) return;` |
| Debug log | `debugPrint(message)` |

---

## 🎯 Best Practices

1. ✅ **Always** check `mounted` before `setState` in async methods
2. ✅ **Always** validate user inputs before processing
3. ✅ **Always** add timeouts to API calls
4. ✅ **Always** validate file sizes before upload
5. ✅ **Always** dispose controllers in `dispose()`
6. ✅ **Always** use try-catch for async operations
7. ✅ **Always** show user-friendly error messages
8. ✅ **Always** provide recovery actions (retry/back)
9. ✅ **Always** use `debugPrint` for logging (not `print`)
10. ✅ **Always** format exceptions before showing to users

---

## ⚠️ Common Mistakes

❌ **Don't:** Use `print()` for logging  
✅ **Do:** Use `debugPrint()`

❌ **Don't:** Show raw exceptions to users  
✅ **Do:** Use `ErrorHandler.formatErrorMessage()`

❌ **Don't:** Forget to check `mounted` before `setState`  
✅ **Do:** Always check `if (!mounted) return;`

❌ **Don't:** Skip timeout on API calls  
✅ **Do:** Add `.timeout(...)` to all network requests

❌ **Don't:** Allow unlimited file sizes  
✅ **Do:** Validate with `ErrorHandler.validateFileSize()`

---

## 🔗 See Also

- `ERRORS_ANALYSIS.md` - Comprehensive error analysis
- `ERROR_HANDLING_SUMMARY.md` - Implementation summary
- `lib/utils/error_handler.dart` - Error handler source code

---

*Quick reference for error handling in PDF App*

