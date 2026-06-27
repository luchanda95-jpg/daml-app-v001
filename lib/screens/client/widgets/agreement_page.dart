// lib/screens/client/agreement_page.dart
import 'package:daml/screens/client/widgets/agreement_form.dart';
import 'package:flutter/material.dart';

class AgreementPage extends StatelessWidget {
  /// Optional title so we can differentiate "Top Up" vs "Borrow" flows
  final String title;

  const AgreementPage({super.key, this.title = 'Agreement', required String loanType});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        // allow default back button
      ),
      body: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(12.0),
          // Display the form you already created
          child: ClientAgreementForm(),
        ),
      ),
    );
  }
}
