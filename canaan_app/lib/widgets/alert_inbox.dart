import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/alert_service.dart';
import '../services/language_service.dart';
import 'animations.dart';

/// Shared Alerts inbox for the Teacher and Student pages (identical
/// behavior — targeting already enforced server-side by AlertService).
///
/// Newest first, All/Unread/Read filter, read/unread styling, realtime
/// INSERT/UPDATE/DELETE, and automatic expiry handling (expired alerts
/// drop out with no refresh via a periodic check + realtime events).
/// Tapping an alert marks ONLY the viewer's own read state.
class AlertInbox extends StatefulWidget {
  /// 'teacher' | 'student'
  final String role;
  final String userId;
  final List<Color> gradient;

  const AlertInbox({
    super.key,
    required this.role,
    this.userId = '',
    this.gradient = const [Color(0xFFB45309), Color(0xFFF59E0B)],
  });

  @override
  State<AlertInbox> createState() => _AlertInboxState();
}

class _AlertInboxState extends State<AlertInbox> {
  String _userId = '';
  String _section = '';
  bool _scopeLoading = true;

  List<Map<String, dynamic>> _alerts = [];
  Map<String, bool> _read = {};
  String _filter = 'all'; // all | unread | read
  bool _isLoading = true;
  String? _loadError;
  Timer? _expiryTimer;
  final List<StreamSubscription> _realtimeSubs = [];

  String get _role => widget.role.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final scope = await AlertService.resolveScope(
      role: _role,
      userId: widget.userId,
    );
    if (!mounted) return;
    setState(() {
      _userId = scope.userId;
      _section = scope.section;
      _scopeLoading = false;
    });
    await _load();
    _watchRealtime();
    // Client-side expiry sweep: hides newly-expired alerts + refreshes
    // badges with no manual refresh (§35–§36).
    _expiryTimer?.cancel();
    _expiryTimer =
        Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _load(silent: true);
    });
  }

  void _watchRealtime() {
    if (_realtimeSubs.isNotEmpty) return;
    final client = Supabase.instance.client;
    for (final t in [
      AlertService.table,
      AlertService.recipientsTable,
    ]) {
      try {
        _realtimeSubs.add(client
            .from(t)
            .stream(primaryKey: ['id'])
            .listen((_) {
              if (mounted) _load(silent: true);
            }));
      } catch (_) {}
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_userId.isEmpty || _section.isEmpty) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError = null;
        });
      }
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final alerts = await AlertService.fetchActive(
        role: _role,
        section: _section,
      );
      final ids = [
        for (final a in alerts) (a['id'] ?? '').toString()
      ].where((s) => s.isNotEmpty).toList();
      final states =
          await AlertService.readStates(_userId, ids);
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _read = states;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load alerts. Check your connection. ($e)';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible {
    switch (_filter) {
      case 'unread':
        return _alerts
            .where((a) =>
                _read[(a['id'] ?? '').toString()] != true)
            .toList();
      case 'read':
        return _alerts
            .where((a) =>
                _read[(a['id'] ?? '').toString()] == true)
            .toList();
      default:
        return _alerts;
    }
  }

  int get _unreadCount => _alerts
      .where((a) => _read[(a['id'] ?? '').toString()] != true)
      .length;

  Future<void> _open(Map<String, dynamic> alert) async {
    final id = (alert['id'] ?? '').toString();
    await AlertService.markAsRead(
      alertId: id,
      userId: _userId,
      role: _role,
      section: _section,
    );
    if (mounted) {
      setState(() => _read[id] = true);
    }
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Text(_emojiOf((alert['alert_type'] ?? '').toString()),
              style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Expanded(
            child: Text((alert['title'] ?? '').toString(),
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ]),
        content: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaChipRow(alert),
                const SizedBox(height: 10),
                Text((alert['message'] ?? '').toString(),
                    style: GoogleFonts.poppins(
                        fontSize: 14, height: 1.6)),
                const SizedBox(height: 10),
                Text(
                    'Published: ${AlertService.prettyDateTime((alert['published_at'] ?? alert['created_at'])?.toString())}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade500)),
              ]),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.gradient.last,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(tr('c_close'),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LangBuilder(
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _filterRow(),
          const SizedBox(height: 12),
          _body(),
        ],
      ),
    );
  }

  Widget _filterRow() {
    final options = [
      ('all', tr('alert_all')),
      ('unread', '${tr('alert_unread')} ($_unreadCount)'),
      ('read', tr('alert_read')),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final (value, label) in options)
          GestureDetector(
            onTap: () =>
                setState(() => _filter = value),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: _filter == value
                    ? LinearGradient(colors: widget.gradient)
                    : null,
                color:
                    _filter == value ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _filter == value
                        ? Colors.transparent
                        : const Color(0xFFE2E8F0)),
              ),
              child: Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _filter == value
                          ? Colors.white
                          : const Color(0xFF475569))),
            ),
          ),
      ],
    );
  }

  Widget _body() {
    if (_scopeLoading || _isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFFF59E0B))),
      );
    }
    if (_userId.isEmpty || _section.isEmpty) {
      return _emptyBox(tr('err_no_section'));
    }
    if (_loadError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded,
              size: 48, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text(_loadError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _load(),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.gradient.last,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text(tr('c_retry'),
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    final items = _visible;
    if (items.isEmpty) {
      return _emptyBox(_alerts.isEmpty
          ? '${tr('alert_no_alerts')}\n${tr('alert_caught_up')}'
          : 'No ${_filter == 'unread' ? tr('alert_unread').toLowerCase() : tr('alert_read').toLowerCase()} alerts.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _card(items[i], i),
    );
  }

  Widget _emptyBox(String message) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        const Text('🔕', style: TextStyle(fontSize: 44)),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151))),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> alert, int index) {
    final id = (alert['id'] ?? '').toString();
    final unread = _read[id] != true;
    final color = _colorOf((alert['alert_type'] ?? '').toString());
    return FadeInSlide(
      index: index % 6,
      child: Material(
        color: unread ? color.withValues(alpha: 0.07) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: () => _open(alert),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: unread
                      ? color.withValues(alpha: 0.45)
                      : const Color(0xFFF1F5F9),
                  width: unread ? 1.5 : 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(_emojiOf((alert['alert_type'] ?? '').toString()),
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                          AlertService.prettyType(
                              (alert['alert_type'] ?? '').toString())
                              .toUpperCase(),
                          style: GoogleFonts.poppins(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: Colors.white)),
                    ),
                    const Spacer(),
                    if (unread)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text((alert['title'] ?? '').toString(),
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: const Color(0xFF111827))),
                  const SizedBox(height: 4),
                  Text((alert['message'] ?? '').toString(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          height: 1.6,
                          color: const Color(0xFF374151))),
                  const SizedBox(height: 10),
                  _metaChipRow(alert),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _metaChipRow(Map<String, dynamic> alert) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _metaChip(
            '${AlertService.prettySendTo((alert['send_to'] ?? '').toString())}'),
        _metaChip(AlertService.prettySection(
            (alert['section'] ?? '').toString())),
        _metaChip(
            'Published: ${AlertService.prettyDateTime((alert['published_at'] ?? alert['created_at'])?.toString())}'),
      ],
    );
  }

  Widget _metaChip(String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 11, color: Colors.grey.shade600)),
    );
  }

  static String _emojiOf(String type) {
    switch (AlertService.normalizeType(type)) {
      case AlertService.typeUrgent:
        return '🚨';
      case AlertService.typeImportant:
        return '❗';
      case AlertService.typeReminder:
        return '🔔';
      case AlertService.typeInstruction:
        return '📋';
      default:
        return '📢';
    }
  }

  static Color _colorOf(String type) {
    switch (AlertService.normalizeType(type)) {
      case AlertService.typeUrgent:
        return const Color(0xFFDC2626);
      case AlertService.typeImportant:
        return const Color(0xFFEA580C);
      case AlertService.typeReminder:
        return const Color(0xFF1565C0);
      case AlertService.typeInstruction:
        return const Color(0xFF6D28D9);
      default:
        return const Color(0xFF0E9F6E);
    }
  }
}
