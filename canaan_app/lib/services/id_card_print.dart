import 'id_card_print_stub.dart'
    if (dart.library.js_interop) 'id_card_print_web.dart' as impl;

/// Opens the browser print dialog for the ID-card print-preview page.
///
/// Returns true when a print dialog was actually invoked (web only).
/// Other platforms return false so the UI can show guidance instead.
Future<bool> printIdCardPage() => impl.printPage();
