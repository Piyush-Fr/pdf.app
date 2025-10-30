# Environment Setup Guide

## 🔐 Overview

All sensitive API keys have been moved from the codebase to environment variables for better security. This guide will help you set up your environment properly.

---

## ✅ What Was Changed

### Security Improvements:
1. ✅ **Removed hardcoded API keys** from all source files
2. ✅ **Created `.env` file** for storing sensitive data
3. ✅ **Added `.env` to `.gitignore`** to prevent accidental commits
4. ✅ **Created `.env.example`** template for team members
5. ✅ **Added `AppConfig` utility** for safe access to environment variables

### Files Modified:
- `lib/main.dart` - Loads environment variables on startup
- `lib/config/app_config.dart` - **NEW** - Configuration utility
- `lib/screens/dashboard.dart` - Uses `AppConfig.geminiApiKey`
- `lib/screens/quiz_setup.dart` - Uses `AppConfig.geminiApiKey`
- `lib/screens/summarizer.dart` - Uses `AppConfig.geminiApiKey`
- `lib/screens/flow_state.dart` - Uses `AppConfig.geminiApiKey`
- `pubspec.yaml` - Added `flutter_dotenv` package
- `.gitignore` - Added `.env` to ignore list

---

## 🚀 Quick Start

### 1. Install Dependencies

```bash
flutter pub get
```

This will install the `flutter_dotenv` package.

### 2. Set Up Environment File

The `.env` file has already been created with your API keys. You can verify it exists:

```bash
# Windows PowerShell
ls .env

# If you need to recreate it, copy from the example:
cp .env.example .env
```

### 3. Verify Configuration

Open `.env` file and ensure it contains:

```env
# Supabase Configuration
SUPABASE_URL=https://lxmyznmgbvbxzjwvbfnr.supabase.co/
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# Google Gemini API Key
GEMINI_API_KEY=AIzaSyBKRquBMtDQsyM7dw8OZlZZe3whX29GrZo
```

### 4. Run the App

```bash
flutter run
```

The app will:
1. Load environment variables from `.env`
2. Initialize Supabase with environment credentials
3. Use Gemini API key from environment for all AI features

---

## 📋 Environment Variables Reference

### Required Variables:

| Variable | Description | Where to Get |
|----------|-------------|--------------|
| `SUPABASE_URL` | Your Supabase project URL | [Supabase Dashboard](https://supabase.com/dashboard) → Project Settings → API |
| `SUPABASE_ANON_KEY` | Supabase anonymous/public key | [Supabase Dashboard](https://supabase.com/dashboard) → Project Settings → API |
| `GEMINI_API_KEY` | Google Gemini API key | [Google AI Studio](https://makersuite.google.com/app/apikey) |

---

## 🔧 Configuration Utility

### Access Environment Variables:

```dart
import 'package:your_app/config/app_config.dart';

// Get API keys
final geminiKey = AppConfig.geminiApiKey;
final supabaseUrl = AppConfig.supabaseUrl;
final supabaseKey = AppConfig.supabaseAnonKey;

// Validate all keys are present
if (AppConfig.validateConfig()) {
  print('All environment variables are set!');
}

// Print status (doesn't log actual keys)
AppConfig.printStatus();
```

### Error Handling:

The `AppConfig` class will throw descriptive errors if keys are missing:

```dart
try {
  final key = AppConfig.geminiApiKey;
} catch (e) {
  print(e); 
  // Output: "GEMINI_API_KEY not found in .env file.
  //          Please add GEMINI_API_KEY=your_api_key to your .env file."
}
```

---

## 👥 Team Setup

### For Team Members:

1. **Copy the example file:**
   ```bash
   cp .env.example .env
   ```

2. **Get API keys from your team lead:**
   - Supabase URL and anon key
   - Gemini API key

3. **Fill in `.env`:**
   ```env
   SUPABASE_URL=your_project_url_here
   SUPABASE_ANON_KEY=your_anon_key_here
   GEMINI_API_KEY=your_gemini_key_here
   ```

4. **Never commit `.env` file!**
   - It's already in `.gitignore`
   - Only commit `.env.example` with placeholder values

---

## 🔒 Security Best Practices

### ✅ DO:
- ✅ Keep `.env` file local only
- ✅ Share keys through secure channels (password managers, encrypted messages)
- ✅ Update `.env.example` when adding new variables
- ✅ Use different keys for development/production
- ✅ Rotate keys periodically
- ✅ Use the `AppConfig` utility to access keys

### ❌ DON'T:
- ❌ Commit `.env` file to version control
- ❌ Hardcode keys in source files
- ❌ Share keys in public channels (Slack, email)
- ❌ Take screenshots showing API keys
- ❌ Log actual key values (use `AppConfig.printStatus()` instead)

---

## 🐛 Troubleshooting

### Error: "Failed to load .env file"

**Solution:**
```bash
# Make sure .env file exists
ls .env

# If not, copy from example
cp .env.example .env

# Fill in your actual API keys
```

### Error: "GEMINI_API_KEY not found in .env file"

**Solution:**
1. Open `.env` file
2. Add the line: `GEMINI_API_KEY=your_actual_key_here`
3. Restart the app

### Error: "SUPABASE_URL not found in .env file"

**Solution:**
1. Open `.env` file
2. Add these lines:
   ```env
   SUPABASE_URL=https://your-project.supabase.co/
   SUPABASE_ANON_KEY=your_anon_key
   ```
3. Restart the app

### App works locally but not after deployment

**Solution:**
- Set environment variables in your deployment platform
- For Firebase Hosting: Use Firebase Functions environment config
- For web hosting: Use server-side API proxy instead of client-side keys

---

## 🌐 Deployment

### Development
- Uses `.env` file locally
- Keys loaded on app startup
- Protected by `.gitignore`

### Production (Recommended Setup)
For production, consider using a backend proxy to hide API keys:

1. **Create backend API** (Node.js/Python/etc.)
2. **Store keys on server** (environment variables)
3. **App calls your backend** instead of external APIs
4. **Backend calls Gemini/Supabase** with keys

This prevents exposing keys in client-side code.

---

## 📱 Platform-Specific Notes

### Android
- `.env` file is bundled with app
- Keys are in compiled APK (not ideal for production)
- Consider using backend proxy for production

### iOS
- Same as Android
- `.env` bundled in app bundle
- Use backend proxy for production apps

### Web
- ⚠️ **WARNING:** Environment variables are visible in web builds
- **MUST use backend proxy** for production web apps
- Never expose API keys in web builds

---

## 🔄 Updating Keys

### To Update a Key:

1. Open `.env` file
2. Update the value:
   ```env
   GEMINI_API_KEY=new_key_here
   ```
3. Restart the app (hot reload won't pick up env changes)

### To Add a New Key:

1. Add to `.env`:
   ```env
   NEW_API_KEY=value_here
   ```

2. Add to `.env.example`:
   ```env
   NEW_API_KEY=your_key_here
   ```

3. Add getter to `lib/config/app_config.dart`:
   ```dart
   static String get newApiKey {
     final key = dotenv.env['NEW_API_KEY'];
     if (key == null || key.isEmpty) {
       throw Exception('NEW_API_KEY not found in .env file.');
     }
     return key;
   }
   ```

4. Use in your code:
   ```dart
   final key = AppConfig.newApiKey;
   ```

---

## ✅ Verification Checklist

Before running the app, verify:

- [ ] `.env` file exists in project root
- [ ] `.env` contains all required variables
- [ ] No hardcoded keys remain in source code
- [ ] `.gitignore` includes `.env`
- [ ] `flutter pub get` completed successfully
- [ ] `.env.example` is up to date

Run this check:
```bash
# Windows PowerShell
ls .env
cat .env.example
git status  # Should NOT show .env file
```

---

## 📞 Support

### Common Issues:

1. **Keys not loading:** Restart the app (hot reload doesn't work for env changes)
2. **File not found:** Make sure `.env` is in project root, not in `lib/`
3. **Keys empty:** Check for typos in variable names (case-sensitive)
4. **Git showing .env:** Run `git rm --cached .env` then commit

### Need Help?

1. Check the `.env.example` file for reference format
2. Review `lib/config/app_config.dart` for available getters
3. Use `AppConfig.printStatus()` to debug configuration
4. Check console output for specific error messages

---

## 🎯 Summary

**Before:**
```dart
// ❌ Hardcoded in source
static const String _geminiApiKey = 'AIzaSy...';
```

**After:**
```dart
// ✅ Loaded from environment
final geminiKey = AppConfig.geminiApiKey;
```

**Benefits:**
- ✅ Keys not in source code
- ✅ Keys not in version control
- ✅ Easy to rotate keys
- ✅ Different keys per environment
- ✅ Better security overall

---

## 🔗 Related Documentation

- `README_ERROR_HANDLING.md` - Error handling guide
- `ERRORS_ANALYSIS.md` - Comprehensive error analysis
- `QUICK_REFERENCE.md` - Code patterns reference

---

*Environment setup completed and secured* 🔒

