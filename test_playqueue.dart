import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() async {
  // Try to read creds from preferences json if possible, or just look at dart code?
  // wait, I can just use flutter test, but flutter test doesn't load shared_preferences.
  // Instead I can look at the preferences xml file for the Android app.
}
