import 'package:flutter_riverpod/flutter_riverpod.dart';

const homeTabHomeIndex = 0;
const homeTabQueueIndex = 1;
const homeTabMuralIndex = 2;
const homeTabProfileIndex = 3;

final homeTabIndexProvider = StateProvider<int>((_) => homeTabHomeIndex);
