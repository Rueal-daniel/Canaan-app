import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/event_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/event_calendar.dart';

/// Teacher Dashboard → Quick Links → Events & Calendar.
///
/// Read-only: teachers can view the calendar + event details but can
/// never create, edit or delete events. Realtime delivery — new Admin
/// events appear automatically.
class TeacherEventsCalendarPage extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String? section;
  const TeacherEventsCalendarPage({
    super.key,
    this.teacherId = '',
    this.teacherName = '',
    this.section,
  });

  @override
  State<TeacherEventsCalendarPage> createState() =>
      _TeacherEventsCalendarPageState();
}

class _TeacherEventsCalendarPageState
    extends State<TeacherEventsCalendarPage> {
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  String? _loadError;

  late int _year;
  late int _month;
  DateTime? _selectedDay;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _fetchEvents();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  void _subscribeRealtime() {
    try {
      _realtimeSub = _client
          .from(EventService.table)
          .stream(primaryKey: ['id'])
          .listen((_) {
        if (mounted) _fetchEvents(silent: true);
      });
    } catch (_) {}
  }

  /// Teachers see every published event (they supervise student events
  /// too). Students-only filtering happens on the student page.
  Future<void> _fetchEvents({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final before =
          _events.map((e) => e['id']).where((id) => id != null).toSet();
      final rows = await _client
          .from(EventService.table)
          .select('*')
          .eq('status', EventService.statusPublished)
          .order('event_date', ascending: true)
          .order('start_time', ascending: true);
      final items = List<Map<String, dynamic>>.from(rows);
      if (mounted) {
        final hadBefore = before.isNotEmpty;
        final fresh = items
            .where((e) => !before.contains(e['id']))
            .toList();
        setState(() {
          _events = items;
          _isLoading = false;
          _loadError = null;
        });
        if (silent && hadBefore && fresh.isNotEmpty) {
          _snack(
            '📅 ${fresh.length == 1 ? 'New event added' : '${fresh.length} new events added'}',
            const Color(0xFF6D28D9),
          );
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _loadError =
              'Could not load events. Check your connection and try again. ($e)';
        });
      }
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Set<String> get _eventKeys {
    final keys = <String>{};
    for (final e in _events) {
      final k = EventService.dateKeyOf(e);
      if (k.isNotEmpty) keys.add(k);
    }
    return keys;
  }

  List<Map<String, dynamic>> get _upcoming =>
      EventService.upcoming(_events);

  List<Map<String, dynamic>> get _dayEvents {
    if (_selectedDay == null) return [];
    final key = EventService.dateKey(_selectedDay!);
    return _events.where((e) => EventService.dateKeyOf(e) == key).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E1065), Color(0xFF6D28D9), Color(0xFFA78BFA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text('Events & Calendar',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchEvents(),
        color: const Color(0xFF6D28D9),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              EventMonthCalendar(
                year: _year,
                month: _month,
                eventKeys: _eventKeys,
                selectedDay: _selectedDay,
                accent: const Color(0xFF6D28D9),
                onDayTap: (d) => setState(() => _selectedDay = d),
                onPrevMonth: () => setState(() {
                  if (_month == 1) {
                    _month = 12;
                    _year--;
                  } else {
                    _month--;
                  }
                }),
                onNextMonth: () => setState(() {
                  if (_month == 12) {
                    _month = 1;
                    _year++;
                  } else {
                    _month++;
                  }
                }),
              ),
              const SizedBox(height: 16),
              if (_selectedDay != null) ...[
                _daySection(),
                const SizedBox(height: 16),
              ],
              Text('Upcoming Events (${_upcoming.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              _body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return FadeInSlide(
      index: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2E1065), Color(0xFF6D28D9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6D28D9).withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.event_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Events & Calendar',
                      style: GoogleFonts.poppins(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Programs shared by the Admin for your section.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.92))),
                ]),
          ),
        ]),
      ),
    );
  }

  Widget _daySection() {
    final items = _dayEvents;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Events on ${EventService.prettyDateOfDay(_selectedDay!)}',
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827)),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedDay = null),
                child: Text('Show all',
                    style: GoogleFonts.poppins(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text('No events on this date.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade500))
          else
            ...items.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: EventCard(
                    event: e,
                    accent: const Color(0xFF6D28D9),
                    onTap: () => showEventDetailDialog(
                      context,
                      e,
                      accent: const Color(0xFF6D28D9),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 50),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF6D28D9))),
      );
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
            onPressed: () => _fetchEvents(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6D28D9),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Retry',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
    }
    if (_upcoming.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          const Text('📅', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text('📅 No upcoming events.\nNew programs from the Admin will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _upcoming.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => FadeInSlide(
        index: 1,
        child: EventCard(
          event: _upcoming[i],
          accent: const Color(0xFF6D28D9),
          onTap: () => showEventDetailDialog(
            context,
            _upcoming[i],
            accent: const Color(0xFF6D28D9),
          ),
        ),
      ),
    );
  }
}
