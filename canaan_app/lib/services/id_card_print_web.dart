import 'package:web/web.dart' as web;

Future<bool> printPage() async {
  try {
    web.window.print();
    return true;
  } catch (_) {
    return false;
  }
}
