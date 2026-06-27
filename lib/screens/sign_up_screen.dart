// lib/screens/sign_up_screen.dart
// ignore_for_file: use_build_context_synchronously, unused_import, deprecated_member_use

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _emailCtl = TextEditingController();
  final TextEditingController _phoneCtl = TextEditingController();
  final TextEditingController _passwordCtl = TextEditingController();
  final TextEditingController _confirmCtl = TextEditingController();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _phoneCtl.dispose();
    _passwordCtl.dispose();
    _confirmCtl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await AuthService.registerWithEmail(
        _nameCtl.text.trim(),
        _emailCtl.text.trim(),
        _phoneCtl.text.trim(),
        _passwordCtl.text,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful!'), duration: Duration(seconds: 1)),
      );

      await Future.delayed(const Duration(milliseconds: 250));
      await AuthService.debugAuthState();

      // ✅ IMPORTANT: wipe stack and go to RootGate
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e)), duration: const Duration(seconds: 3)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('already registered')) return 'Email already registered.';
    if (msg.contains('reserved for admin')) return 'This email is reserved for admin.';
    if (msg.contains('Invalid registration')) return 'Invalid registration data.';
    if (msg.contains('Network is unreachable')) return 'Network error. Check your connection.';
    if (msg.contains('Timeout')) return 'Request timeout. Please try again.';
    return 'Registration failed: ${msg.replaceAll('Exception: ', '')}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),

              // ✅ LOGO instead of icon
              Center(
                child: Container(
                  width: 86,
                  height: 86,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: colorScheme.outline.withOpacity(0.18)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Text(
                'Create Account',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Fill in your details to get started',
                style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface.withOpacity(0.7)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 26),

              TextFormField(
                controller: _nameCtl,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Please enter your full name';
                  if (value.trim().length < 2) return 'Name must be at least 2 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailCtl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Please enter your email';
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _phoneCtl,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Please enter your phone number';
                  if (value.trim().length < 9) return 'Please enter a valid phone number';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordCtl,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter a password';
                  if (value.length < 6) return 'Password must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmCtl,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please confirm your password';
                  if (value != _passwordCtl.text) return 'Passwords do not match';
                  return null;
                },
              ),

              const SizedBox(height: 26),

              ElevatedButton(
                onPressed: _loading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 4,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                      )
                    : const Text(
                        'Create Account',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
              ),

              const SizedBox(height: 18),

              OutlinedButton(
                onPressed: _loading ? null : () => Navigator.of(context).pushReplacementNamed('/signin'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: colorScheme.primary),
                ),
                child: Text(
                  'Already have an account? Sign In',
                  style: TextStyle(fontSize: 16, color: colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
