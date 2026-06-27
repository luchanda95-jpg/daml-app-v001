// lib/screens/branch/widgets/form_fields.dart
import 'package:flutter/material.dart';

/// A simple amount input with basic non-negative validation.
/// Keeps behavior minimal so parent can own parsing/logic.
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? Function(String?)? validator;

  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix,
    this.validator,
  });

  String? _defaultValidator(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final cleaned = s.replaceAll(',', '').trim();
    final val = double.tryParse(cleaned);
    if (val == null) return 'Invalid number';
    if (val < 0) return 'Cannot be negative';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, suffixText: suffix ?? 'ZMW'),
      validator: validator ?? _defaultValidator,
    );
  }
}

/// A simple integer/count field with minimum validation.
class CountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  const CountField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
  });

  String? _defaultValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = int.tryParse(v.trim());
    if (n == null) return 'Invalid number';
    if (n < 0) return 'Cannot be negative';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: validator ?? _defaultValidator,
    );
  }
}
