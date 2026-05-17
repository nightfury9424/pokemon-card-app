import 'package:flutter/foundation.dart';

class AssetNotifier extends ChangeNotifier {
  static final instance = AssetNotifier._();
  AssetNotifier._();
  void notifyChanged() => notifyListeners();
}
