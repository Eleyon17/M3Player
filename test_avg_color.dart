import 'package:flutter/material.dart';

Color averageColors(List<Color> colors) {
  if (colors.isEmpty) return const Color(0xFF8C6DB4);
  int r = 0, g = 0, b = 0;
  for (var c in colors) {
    r += c.red;
    g += c.green;
    b += c.blue;
  }
  return Color.fromARGB(
    255,
    (r / colors.length).round(),
    (g / colors.length).round(),
    (b / colors.length).round(),
  );
}

void main() {
  print(averageColors([Colors.red, Colors.blue]));
}
