// lib/providers/loading_provider.dart
import 'package:flutter/material.dart';

class LoadingProvider extends ChangeNotifier {
  bool _isLoading = false;
  String _message = "Please wait...";

  bool get isLoading => _isLoading;
  String get message => _message;

  void show(String message) {
    _message = message;
    _isLoading = true;
    notifyListeners();
  }

  void hide() {
    _isLoading = false;
    notifyListeners();
  }
}