// lib/services/supabase_config.dart
// Use only the public anon key here. Never use service role key in Flutter.

class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qmgcthumnfgjbjuefcqa.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFtZ2N0aHVtbmZnamJqdWVmY3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5Mzg5NTEsImV4cCI6MjA5ODUxNDk1MX0.KtRI9G-OhMAj2skNPUx7QuiGb7svHRFtFukLcVAiXuM',
  );

  static const String applicationBucket = String.fromEnvironment(
    'SUPABASE_APPLICATION_BUCKET',
    defaultValue: 'application-pdfs',
  );

  static bool get isConfigured {
    return url.startsWith('https://') &&
        !url.contains('PASTE_SUPABASE') &&
        anonKey.isNotEmpty &&
        !anonKey.contains('PASTE_SUPABASE') &&
        !anonKey.contains('PASTE_YOUR');
  }
}