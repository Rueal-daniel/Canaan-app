import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/event_service.dart';
import '../../services/notification_service.dart';
import '../../services/session_service.dart';
import '../../widgets/animations.dart';
import '../../widgets/event_calendar.dart';

/// Admin → Management → Events & Calendar.
///
/// Full management: single events, whole-month programs, a calendar view
/// with red event indicators, and a searchable/filterable event list
/// (View | Edit | Delete + publish/unpublish). Writes go to the `events`
/// table with realtime delivery; publishing fans out bell notifications
/// to the relevant audience/section only.
class AdminEventsCalendarPage extends StatefulWidget {
  final String adminName;
  const AdminEventsCalendarPage({super.key, this.adminName = ''});

  @override
  State<AdminEventsCalendarPage> createState() =>
      _AdminEventsCalendarPageState();
}

class _AdminEventsCalendarPageState extends State<AdminEventsCalendarPage> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();
  final _attachUrlController = TextEditingController();
  final _attachNameController = TextEditingController();

  DateTime? _eventDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  String _eventType = EventService.typeSundaySchool;
  String _audience = EventService.audienceEveryone;
  Set<String> _sections = {EventService.sectionAll};
  bool _publishNow = true;

  bool _showForm = false;
  bool _showMonthly = false;
  bool _isSaving = false;
  bool _isLoading = true;
  String? _loadError;
  int? _editingId;

  // Monthly program builder.
  DateTime _monthCursor =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _monthSelectedDay;
  final List<Map<String, dynamic>> _monthlyDrafts = [];
  bool _isPublishingMonth = false;

  // Calendar view.
  late int _calYear;
  late int _calMonth;
  DateTime? _selectedDay;

  // Filters.
  String _search = '';
  String _filterMonth = '';
  String _filterType = '';
  String _filterSection = '';
  String _filterAudience = '';
  String _filterStatus = '';

  List<Map<String, dynamic>> _events = [];
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calYear = now.year;
    _calMonth = now.month;
    _fetchEvents();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descController.dispose();
    _attachUrlController.dispose();
    _attachNameController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
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

  Future<void> _fetchEvents({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final rows = await _client
          .from(EventService.table)
          .select('*')
          .order('event_date', ascending: true)
          .order('start_time', ascending: true);
      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(rows);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
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

  Future<Map<String, String?>> _adminIdentity() async {
    var name = widget.adminName;
    String? id;
    try {
      final session = await SessionService.getSession();
      if (session != null && session.role == UserRole.admin.name) {
        id = session.userId;
        if (name.isEmpty) {
          final auth = AuthService();
          final profile = await auth.getUserById(
              userId: session.userId, role: UserRole.admin);
          name = (profile?['full_name'] ?? '').toString();
        }
      }
    } catch (_) {}
    return {'name': name.isEmpty ? 'Admin' : name, 'id': id};
  }

  String _fmtTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final mm = t.minute.toString().padLeft(2, '0');
    final ap = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$mm $ap';
  }

  Future<void> _pickDate({DateTime? initial, required ValueChanged<DateTime> onPick}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) onPick(picked);
  }

  Future<void> _pickTime({TimeOfDay? initial, required ValueChanged<TimeOfDay> onPick}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 10, minute: 0),
    );
    if (picked != null) onPick(picked);
  }

  // -- single event save ---------------------------------------------------------

  Future<void> _saveSingle() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_eventDate == null) {
      _snack('Please pick an event date.', Colors.orange);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final identity = await _adminIdentity();
      final now = DateTime.now().toIso8601String();
      final dateStr = EventService.dateKey(_eventDate!);
      final isNew = _editingId == null;
      final wasPublished = _publishNow;
      final payload = <String, dynamic>{
        'title': _titleController.text.trim(),
        'event_date': dateStr,
        'start_time': _startTime == null ? '' : _fmtTime(_startTime!),
        'end_time': _endTime == null ? '' : _fmtTime(_endTime!),
        'location': _locationController.text.trim(),
        'event_type': _eventType,
        'description': _descController.text.trim(),
        'audience': _audience,
        'section': EventService.sectionSlugForWrite(_sections.toList()),
        'attachment_url': _attachUrlController.text.trim(),
        'attachment_name': _attachNameController.text.trim(),
        'status': _publishNow
            ? EventService.statusPublished
            : EventService.statusDraft,
        'updated_at': now,
      };
      int? savedId = _editingId;
      final savedTitle = _titleController.text.trim();
      final savedDateStr = dateStr;
      final savedAudience = _audience;
      final savedSections =
          EventService.sectionSlugForWrite(_sections.toList()).split(',');
      if (_editingId != null) {
        await _client
            .from(EventService.table)
            .update(payload)
            .eq('id', _editingId!);
        _snack('✅ Event updated successfully!', Colors.green);
      } else {
        payload['created_by'] = identity['name'];
        if ((identity['id'] ?? '').isNotEmpty) {
          payload['created_by_id'] = identity['id'];
        }
        if (_publishNow) payload['published_at'] = now;
        try {
          final created = await _client
              .from(EventService.table)
              .insert(payload)
              .select('id')
              .single();
          savedId = (created['id'] as num?)?.toInt();
        } catch (_) {
          payload.remove('created_by_id');
          final created = await _client
              .from(EventService.table)
              .insert(payload)
              .select('id')
              .single();
          savedId = (created['id'] as num?)?.toInt();
        }
        _snack(
          _publishNow
              ? '✅ Event published successfully!'
              : '✅ Event saved as draft.',
          Colors.green,
        );
      }
      _resetForm();
      await _fetchEvents(silent: true);
      // 🔔 Notify the relevant audience/section (new published events only).
      if (isNew && wasPublished && savedId != null) {
        try {
          await NotificationService.eventPublished(
            eventId: savedId.toString(),
            title: savedTitle.isEmpty ? 'Event' : savedTitle,
            dateLabel: EventService.prettyDate({'event_date': savedDateStr}),
            audience: savedAudience,
            sections: savedSections,
          );
        } catch (_) {}
      }
    } catch (e) {
      _snack('Could not save. Please try again. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _titleController.clear();
    _locationController.clear();
    _descController.clear();
    _attachUrlController.clear();
    _attachNameController.clear();
    if (mounted) {
      setState(() {
        _eventDate = null;
        _startTime = null;
        _endTime = null;
        _eventType = EventService.typeSundaySchool;
        _audience = EventService.audienceEveryone;
        _sections = {EventService.sectionAll};
        _publishNow = true;
        _editingId = null;
        _showForm = false;
      });
    }
  }

  void _startEdit(Map<String, dynamic> event) {
    _titleController.text = (event['title'] ?? '').toString();
    _locationController.text = (event['location'] ?? '').toString();
    _descController.text = (event['description'] ?? '').toString();
    _attachUrlController.text = (event['attachment_url'] ?? '').toString();
    _attachNameController.text = (event['attachment_name'] ?? '').toString();
    setState(() {
      _eventDate = EventService.dateOf(event);
      _eventType =
          EventService.normalizeType(event['event_type']?.toString());
      _audience =
          EventService.normalizeAudience(event['audience']?.toString());
      _sections = EventService.sectionsOf(event).toSet();
      _publishNow = EventService.isPublished(event);
      _startTime = _parseTime((event['start_time'] ?? '').toString());
      _endTime = _parseTime((event['end_time'] ?? '').toString());
      _editingId = (event['id'] as num?)?.toInt();
      _showForm = true;
      _showMonthly = false;
    });
    _scrollController.animateTo(0,
        duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
    _snack('Editing mode — update the fields and save.',
        const Color(0xFF1565C0));
  }

  TimeOfDay? _parseTime(String raw) {
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) return null;
    try {
      final m = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$').firstMatch(s);
      if (m == null) return null;
      var h = int.parse(m.group(1)!);
      final min = int.parse(m.group(2)!);
      final ap = m.group(3);
      if (ap == 'PM' && h < 12) h += 12;
      if (ap == 'AM' && h == 12) h = 0;
      return TimeOfDay(hour: h % 24, minute: min);
    } catch (_) {
      return null;
    }
  }

  void _confirmDelete(Map<String, dynamic> event) {
    final id = (event['id'] as num?)?.toInt();
    if (id == null) return;
    final title = (event['title'] ?? 'this event').toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Event?',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17)),
        content: Text('Are you sure you want to delete "$title"?',
            style:
                GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _client
                    .from(EventService.table)
                    .delete()
                    .eq('id', id);
                if (_editingId == id) _resetForm();
                await _fetchEvents(silent: true);
                _snack('Event deleted.', Colors.green);
              } catch (e) {
                _snack('Could not delete. Please try again. ($e)', Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Delete',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePublish(Map<String, dynamic> event) async {
    final id = (event['id'] as num?)?.toInt();
    if (id == null) return;
    final currently = EventService.isPublished(event);
    try {
      final now = DateTime.now().toIso8601String();
      await _client.from(EventService.table).update({
        'status': currently
            ? EventService.statusDraft
            : EventService.statusPublished,
        'published_at': currently ? null : now,
        'updated_at': now,
      }).eq('id', id);
      await _fetchEvents(silent: true);
      _snack(
        currently ? 'Event unpublished (draft).' : '✅ Event published!',
        Colors.green,
      );
      if (!currently) {
        try {
          await NotificationService.eventPublished(
            eventId: id.toString(),
            title: (event['title'] ?? 'Event').toString(),
            dateLabel: EventService.prettyDate(event),
            audience: (event['audience'] ?? 'everyone').toString(),
            sections:
                (event['section']?.toString() ?? 'all').split(','),
          );
        } catch (_) {}
      }
    } catch (e) {
      _snack('Could not update status. ($e)', Colors.red);
    }
  }

  // -- monthly program -----------------------------------------------------------

  List<Map<String, dynamic>> get _monthExisting => _events.where((e) {
        final d = EventService.dateOf(e);
        return d != null &&
            d.year == _monthCursor.year &&
            d.month == _monthCursor.month;
      }).toList();

  Set<String> get _monthEventKeys {
    final keys = <String>{};
    for (final e in _monthExisting) {
      final k = EventService.dateKeyOf(e);
      if (k.isNotEmpty) keys.add(k);
    }
    for (final d in _monthlyDrafts) {
      final k = (d['event_date'] ?? '').toString();
      if (k.isNotEmpty) keys.add(k);
    }
    return keys;
  }

  List<Map<String, dynamic>> _dayItems(DateTime day) {
    final key = EventService.dateKey(day);
    final existing = _monthExisting
        .where((e) => EventService.dateKeyOf(e) == key)
        .toList();
    final drafts = _monthlyDrafts
        .where((d) => (d['event_date'] ?? '').toString() == key)
        .toList();
    return [...existing, ...drafts];
  }

  void _openDayComposer(DateTime day) {
    final titleCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    TimeOfDay? start = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay? end = const TimeOfDay(hour: 12, minute: 0);
    String type = EventService.typeSundaySchool;
    String audience = EventService.audienceEveryone;
    Set<String> sections = {EventService.sectionAll};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Program — ${EventService.prettyDateOfDay(day)}',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._dayItems(day).map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '• ${(e['title'] ?? '').toString()}'
                              '${(e['start_time'] ?? '').toString().isNotEmpty ? ' · ${(e['start_time'] ?? '').toString()}${(e['end_time'] ?? '').toString().isNotEmpty ? ' – ${(e['end_time'] ?? '').toString()}' : ''}' : ''}',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: const Color(0xFF374151)),
                            ),
                          ),
                          if (e['id'] == null)
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: Colors.red, size: 20),
                              tooltip: 'Remove draft',
                              onPressed: () {
                                setState(() => _monthlyDrafts.remove(e));
                                Navigator.pop(ctx);
                                _snack('Draft removed.', Colors.grey.shade600);
                              },
                            ),
                        ],
                      ),
                    )),
                const SizedBox(height: 8),
                _sheetLabel('Event Title'),
                TextField(
                  controller: titleCtrl,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: _sheetDecoration('e.g. Sunday School'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sheetLabel('Start Time'),
                          _timeChip(
                            start == null ? 'Pick' : _fmtTime(start!),
                            () async {
                              final p = await showTimePicker(
                                context: ctx,
                                initialTime: start ??
                                    const TimeOfDay(hour: 10, minute: 0),
                              );
                              if (p != null) setSheet(() => start = p);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sheetLabel('End Time'),
                          _timeChip(
                            end == null ? 'Pick' : _fmtTime(end!),
                            () async {
                              final p = await showTimePicker(
                                context: ctx,
                                initialTime: end ??
                                    const TimeOfDay(hour: 12, minute: 0),
                              );
                              if (p != null) setSheet(() => end = p);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _sheetLabel('Location'),
                TextField(
                  controller: locCtrl,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration:
                      _sheetDecoration('e.g. Canaan Sunday School'),
                ),
                const SizedBox(height: 12),
                _sheetLabel('Event Type'),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    (EventService.typeSundaySchool, 'Sunday School'),
                    (EventService.typeActivity, 'Activity'),
                    (EventService.typeSpecial, 'Special Program'),
                    (EventService.typeOthers, 'Others'),
                  ]
                      .map((o) => DropdownMenuItem(
                            value: o.$1,
                            child: Text(o.$2,
                                style: GoogleFonts.poppins(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setSheet(() => type = v);
                  },
                  decoration: _sheetDecoration('Type'),
                ),
                const SizedBox(height: 12),
                _sheetLabel('Target Audience'),
                DropdownButtonFormField<String>(
                  value: audience,
                  items: const [
                    (EventService.audienceEveryone, 'Everyone'),
                    (EventService.audienceStudents, 'Students'),
                    (EventService.audienceTeachers, 'Teachers'),
                  ]
                      .map((o) => DropdownMenuItem(
                            value: o.$1,
                            child: Text(o.$2,
                                style: GoogleFonts.poppins(fontSize: 14)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setSheet(() => audience = v);
                  },
                  decoration: _sheetDecoration('Audience'),
                ),
                const SizedBox(height: 12),
                _sheetLabel('Section'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final o in [
                      (EventService.sectionAll, 'All Sections'),
                      (EventService.sectionSubJunior, 'Sub Junior'),
                      (EventService.sectionJunior, 'Junior'),
                      (EventService.sectionSenior, 'Senior'),
                    ])
                      FilterChip(
                        label: Text(o.$2,
                            style: GoogleFonts.poppins(fontSize: 12.5)),
                        selected: sections.contains(o.$1),
                        onSelected: (_) => setSheet(() {
                          if (o.$1 == EventService.sectionAll) {
                            sections = {EventService.sectionAll};
                          } else {
                            final next = Set<String>.from(sections)
                              ..remove(EventService.sectionAll);
                            if (next.contains(o.$1)) {
                              next.remove(o.$1);
                            } else {
                              next.add(o.$1);
                            }
                            sections =
                                next.isEmpty ? {EventService.sectionAll} : next;
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _sheetLabel('Description / Details'),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration:
                      _sheetDecoration('e.g. Bible Teaching'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Please enter an event title.',
                                style: GoogleFonts.poppins()),
                            backgroundColor: Colors.orange,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }
                      setState(() {
                        _monthlyDrafts.add({
                          'title': titleCtrl.text.trim(),
                          'event_date': EventService.dateKey(day),
                          'start_time':
                              start == null ? '' : _fmtTime(start!),
                          'end_time': end == null ? '' : _fmtTime(end!),
                          'location': locCtrl.text.trim(),
                          'event_type': type,
                          'description': descCtrl.text.trim(),
                          'audience': audience,
                          'section': EventService.sectionSlugForWrite(
                              sections.toList()),
                          'attachment_url': '',
                          'attachment_name': '',
                        });
                        _monthSelectedDay = day;
                      });
                      Navigator.pop(ctx);
                      _snack(
                        'Added to ${EventService.prettyDateOfDay(day)} — publish the month when ready.',
                        const Color(0xFF1565C0),
                      );
                    },
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text('Add to This Day',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1565C0),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _publishMonthly() async {
    if (_isPublishingMonth || _monthlyDrafts.isEmpty) return;
    setState(() => _isPublishingMonth = true);
    try {
      final identity = await _adminIdentity();
      final now = DateTime.now().toIso8601String();
      var published = 0;
      final saved = <Map<String, dynamic>>[];
      for (final d in List<Map<String, dynamic>>.from(_monthlyDrafts)) {
        final payload = <String, dynamic>{
          'title': d['title'],
          'event_date': d['event_date'],
          'start_time': d['start_time'],
          'end_time': d['end_time'],
          'location': d['location'],
          'event_type': d['event_type'],
          'description': d['description'],
          'audience': d['audience'],
          'section': d['section'],
          'attachment_url': '',
          'attachment_name': '',
          'status': EventService.statusPublished,
          'created_by': identity['name'],
          'published_at': now,
          'updated_at': now,
        };
        if ((identity['id'] ?? '').isNotEmpty) {
          payload['created_by_id'] = identity['id'];
        }
        try {
          final created = await _client
              .from(EventService.table)
              .insert(payload)
              .select('id')
              .single();
          final id = (created['id'] as num?)?.toInt();
          saved.add({...payload, 'id': id});
          published++;
        } catch (_) {
          payload.remove('created_by_id');
          try {
            final created = await _client
                .from(EventService.table)
                .insert(payload)
                .select('id')
                .single();
            final id = (created['id'] as num?)?.toInt();
            saved.add({...payload, 'id': id});
            published++;
          } catch (_) {}
        }
      }
      setState(() => _monthlyDrafts.clear());
      await _fetchEvents(silent: true);
      _snack('✅ Monthly program published! ($published events)',
          Colors.green);
      // 🔔 One notification per event, audience/section scoped.
      for (final e in saved) {
        try {
          await NotificationService.eventPublished(
            eventId: (e['id'] ?? '').toString(),
            title: (e['title'] ?? 'Event').toString(),
            dateLabel: EventService.prettyDate(e),
            audience: (e['audience'] ?? 'everyone').toString(),
            sections: (e['section']?.toString() ?? 'all').split(','),
          );
        } catch (_) {}
      }
    } catch (e) {
      _snack('Could not publish month. ($e)', Colors.red);
    } finally {
      if (mounted) setState(() => _isPublishingMonth = false);
    }
  }

  // -- filters ---------------------------------------------------------------------

  Set<String> get _calEventKeys {
    final keys = <String>{};
    for (final e in _events) {
      final k = EventService.dateKeyOf(e);
      if (k.isNotEmpty) keys.add(k);
    }
    return keys;
  }

  List<Map<String, dynamic>> get _selectedDayEventRows {
    if (_selectedDay == null) return [];
    final key = EventService.dateKey(_selectedDay!);
    return _events.where((e) => EventService.dateKeyOf(e) == key).toList();
  }

  List<String> get _monthOptions {
    final set = <String>{};
    for (final e in _events) {
      final d = EventService.dateOf(e);
      if (d != null) {
        set.add(
            '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}');
      }
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  String _monthOptionLabel(String ym) {
    final parts = ym.split('-');
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 1;
    if (y == 0) return ym;
    return EventService.monthLabel(y, m);
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _events.where((e) {
      if (_filterMonth.isNotEmpty) {
        final d = EventService.dateOf(e);
        final ym = d == null
            ? ''
            : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
        if (ym != _filterMonth) return false;
      }
      if (_filterType.isNotEmpty &&
          EventService.normalizeType(e['event_type']?.toString()) !=
              _filterType) {
        return false;
      }
      if (_filterAudience.isNotEmpty &&
          EventService.normalizeAudience(e['audience']?.toString()) !=
              _filterAudience) {
        return false;
      }
      if (_filterSection.isNotEmpty) {
        final secs = EventService.sectionsOf(e);
        if (!secs.contains(EventService.sectionAll) &&
            !secs.contains(_filterSection)) {
          return false;
        }
      }
      if (_filterStatus.isNotEmpty &&
          EventService.normalizeStatus(e['status']?.toString()) !=
              _filterStatus) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = '${e['title']} ${e['description']} ${e['location']}'
            .toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  // -- build --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
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
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _showForm = !_showForm;
                          if (_showForm) {
                            _showMonthly = false;
                            _editingId = null;
                          }
                        }),
                        icon: const Icon(Icons.add_rounded, size: 22),
                        label: Text('Add Event',
                            style: GoogleFonts.poppins(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _showMonthly = !_showMonthly;
                          if (_showMonthly) _showForm = false;
                        }),
                        icon: const Icon(Icons.calendar_month_rounded,
                            size: 20),
                        label: Text('Monthly Program',
                            style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6D28D9),
                          side: const BorderSide(
                              color: Color(0xFF6D28D9), width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_showForm) ...[
                const SizedBox(height: 12),
                _formCard(),
              ],
              if (_showMonthly) ...[
                const SizedBox(height: 12),
                _monthlyCard(),
              ],
              const SizedBox(height: 20),
              Text('Calendar',
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827))),
              const SizedBox(height: 12),
              EventMonthCalendar(
                year: _calYear,
                month: _calMonth,
                eventKeys: _calEventKeys,
                selectedDay: _selectedDay,
                accent: const Color(0xFF1565C0),
                onDayTap: (d) =>
                    setState(() => _selectedDay = d),
                onPrevMonth: () => setState(() {
                  if (_calMonth == 1) {
                    _calMonth = 12;
                    _calYear--;
                  } else {
                    _calMonth--;
                  }
                }),
                onNextMonth: () => setState(() {
                  if (_calMonth == 12) {
                    _calMonth = 1;
                    _calYear++;
                  } else {
                    _calMonth++;
                  }
                }),
              ),
              if (_selectedDay != null) ...[
                const SizedBox(height: 12),
                _dayEventsCard(),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text('Events (${_filtered.length})',
                        style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _searchBox(),
              const SizedBox(height: 10),
              _filtersRow(),
              const SizedBox(height: 12),
              _eventsList(),
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
            colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
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
                  Text(
                      'Single events or a whole month\u2019s program — published live to teachers & students.',
                      style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.9))),
                ]),
          ),
        ]),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      labelStyle:
          GoogleFonts.poppins(color: Colors.grey.shade600, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0), width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2)),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  Widget _formCard() {
    final isEditing = _editingId != null;
    return FadeInSlide(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(isEditing ? 'Edit Event' : 'Add Event',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                TextButton.icon(
                  onPressed: _isSaving ? null : _resetForm,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('Cancel',
                      style: GoogleFonts.poppins(fontSize: 12.5)),
                ),
              ]),
              const SizedBox(height: 14),
              _fieldLabel('Event Title'),
              TextFormField(
                controller: _titleController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration:
                    _inputDecoration('Title', 'e.g. Bible Quiz'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 14),
              _fieldLabel('Event Date'),
              InkWell(
                onTap: () => _pickDate(
                  initial: _eventDate,
                  onPick: (d) => setState(() => _eventDate = d),
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 20, color: Color(0xFF1565C0)),
                      const SizedBox(width: 10),
                      Text(
                        _eventDate == null
                            ? 'Pick a date'
                            : EventService.prettyDateOfDay(_eventDate!),
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: _eventDate == null
                                ? Colors.grey.shade400
                                : const Color(0xFF111827)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Start Time'),
                        InkWell(
                          onTap: () => _pickTime(
                            initial: _startTime,
                            onPick: (t) =>
                                setState(() => _startTime = t),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 15),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.grey.shade200),
                            ),
                            child: Text(
                              _startTime == null
                                  ? 'Start'
                                  : _fmtTime(_startTime!),
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: _startTime == null
                                      ? Colors.grey.shade400
                                      : const Color(0xFF111827)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('End Time'),
                        InkWell(
                          onTap: () => _pickTime(
                            initial: _endTime,
                            onPick: (t) => setState(() => _endTime = t),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 15),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.grey.shade200),
                            ),
                            child: Text(
                              _endTime == null
                                  ? 'End'
                                  : _fmtTime(_endTime!),
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: _endTime == null
                                      ? Colors.grey.shade400
                                      : const Color(0xFF111827)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _fieldLabel('Location'),
              TextFormField(
                controller: _locationController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Location', 'e.g. Canaan Sunday School'),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Event Type'),
              DropdownButtonFormField<String>(
                value: _eventType,
                items: const [
                  (EventService.typeSundaySchool, 'Sunday School'),
                  (EventService.typeActivity, 'Activity'),
                  (EventService.typeSpecial, 'Special Program'),
                  (EventService.typeOthers, 'Others'),
                ]
                    .map((o) => DropdownMenuItem(
                          value: o.$1,
                          child: Text(o.$2,
                              style:
                                  GoogleFonts.poppins(fontSize: 14)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _eventType = v);
                },
                decoration: _inputDecoration('Type', 'Event type'),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Description / Details'),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Details', 'What happens at this event?'),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Target Audience'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: RadioGroup<String>(
                  groupValue: _audience,
                  onChanged: (v) {
                    if (_isSaving || v == null) return;
                    setState(() => _audience = v);
                  },
                  child: Column(children: [
                    for (final o in [
                      (EventService.audienceEveryone, 'Everyone'),
                      (EventService.audienceStudents, 'Students'),
                      (EventService.audienceTeachers, 'Teachers'),
                    ])
                      RadioListTile<String>(
                        value: o.$1,
                        title: Text(o.$2,
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF111827))),
                        activeColor: const Color(0xFF1565C0),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        dense: true,
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              _fieldLabel('Section'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in [
                    (EventService.sectionAll, 'All Sections'),
                    (EventService.sectionSubJunior, 'Sub Junior'),
                    (EventService.sectionJunior, 'Junior'),
                    (EventService.sectionSenior, 'Senior'),
                  ])
                    FilterChip(
                      label: Text(o.$2,
                          style: GoogleFonts.poppins(fontSize: 12.5)),
                      selected: _sections.contains(o.$1),
                      selectedColor: const Color(0xFF1565C0)
                          .withValues(alpha: 0.15),
                      checkmarkColor: const Color(0xFF1565C0),
                      onSelected: (_) => setState(() {
                        if (o.$1 == EventService.sectionAll) {
                          _sections = {EventService.sectionAll};
                        } else {
                          final next = Set<String>.from(_sections)
                            ..remove(EventService.sectionAll);
                          if (next.contains(o.$1)) {
                            next.remove(o.$1);
                          } else {
                            next.add(o.$1);
                          }
                          _sections = next.isEmpty
                              ? {EventService.sectionAll}
                              : next;
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              _fieldLabel('Optional Attachment (link)'),
              TextFormField(
                controller: _attachUrlController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Attachment', 'Paste an optional link'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _attachNameController,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: _inputDecoration(
                    'Attachment label', 'e.g. Program leaflet'),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                value: _publishNow,
                onChanged: _isSaving
                    ? null
                    : (v) => setState(() => _publishNow = v),
                title: Text('Publish Event',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF111827))),
                subtitle: Text(
                  _publishNow
                      ? 'Visible to teachers & students immediately.'
                      : 'Saved as draft — only Admins can see it.',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5, color: Colors.grey.shade600),
                ),
                activeColor: const Color(0xFF1565C0),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              if (_isSaving) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(
                    color: Color(0xFF1565C0),
                    backgroundColor: Color(0xFFF1F5F9),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSingle,
                  icon: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.event_rounded, size: 20),
                  label: Text(
                    isEditing
                        ? 'Update Event'
                        : (_publishNow
                            ? '📅 Publish Event'
                            : 'Save as Draft'),
                    style: GoogleFonts.poppins(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF1565C0)
                        .withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthlyCard() {
    return FadeInSlide(
      index: 1,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE9D5FF)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Create Monthly Program',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827))),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _showMonthly = false;
                    _monthlyDrafts.clear();
                  }),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('Close',
                      style: GoogleFonts.poppins(fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pick the month, tap any date, add that day\u2019s program — then publish the whole month at once.',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _monthCursor.month,
                    isExpanded: true,
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(EventService.fullMonths[m - 1],
                                  style: GoogleFonts.poppins(
                                      fontSize: 13.5),
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _monthCursor = DateTime(_monthCursor.year, v, 1);
                        _monthSelectedDay = null;
                      });
                    },
                    decoration: _inputDecoration('Month', 'Month'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<int>(
                    value: _monthCursor.year,
                    items: List.generate(7,
                            (i) => DateTime.now().year - 2 + i)
                        .map((y) => DropdownMenuItem(
                              value: y,
                              child: Text('$y',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13.5)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _monthCursor =
                            DateTime(v, _monthCursor.month, 1);
                        _monthSelectedDay = null;
                      });
                    },
                    decoration: _inputDecoration('Year', 'Year'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            EventMonthCalendar(
              year: _monthCursor.year,
              month: _monthCursor.month,
              eventKeys: _monthEventKeys,
              selectedDay: _monthSelectedDay,
              accent: const Color(0xFF6D28D9),
              showNav: false,
              onDayTap: (d) {
                setState(() => _monthSelectedDay = d);
                _openDayComposer(d);
              },
            ),
            if (_monthSelectedDay != null) ...[
              const SizedBox(height: 12),
              Text(
                EventService.prettyDateOfDay(_monthSelectedDay!),
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827)),
              ),
              const SizedBox(height: 8),
              ..._dayItems(_monthSelectedDay!).map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${(e['title'] ?? '').toString()}'
                            '${(e['start_time'] ?? '').toString().isNotEmpty ? '\n${(e['start_time'] ?? '').toString()}${(e['end_time'] ?? '').toString().isNotEmpty ? ' – ${(e['end_time'] ?? '').toString()}' : ''}' : ''}'
                            '${e['id'] == null ? '\n(Draft — not published yet)' : ''}',
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: const Color(0xFF374151)),
                          ),
                        ),
                        if (e['id'] == null)
                          IconButton(
                            icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.red,
                                size: 20),
                            onPressed: () => setState(
                                () => _monthlyDrafts.remove(e)),
                          ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_monthlyDrafts.length} draft${_monthlyDrafts.length == 1 ? '' : 's'} ready · ${_monthExisting.length} already on the calendar',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6D28D9)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_isPublishingMonth || _monthlyDrafts.isEmpty)
                    ? null
                    : _publishMonthly,
                icon: _isPublishingMonth
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.publish_rounded, size: 20),
                label: Text(
                  'Publish Monthly Program (${_monthlyDrafts.length})',
                  style: GoogleFonts.poppins(
                      fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF6D28D9)
                      .withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayEventsCard() {
    final rows = _selectedDayEventRows;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  EventService.prettyDateOfDay(_selectedDay!),
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF111827)),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedDay = null),
                child: Text('Clear',
                    style: GoogleFonts.poppins(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text('No events on this date.',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade500))
          else
            ...rows.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                        left: BorderSide(
                            color: EventService.isPublished(e)
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFF59E0B),
                            width: 4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${(e['title'] ?? '').toString()}'
                          '${EventService.timeRangeOf(e).isNotEmpty ? '\n${EventService.timeRangeOf(e)}' : ''}'
                          '\n${EventService.prettySections(e)}${EventService.isPublished(e) ? '' : ' · Draft'}',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: const Color(0xFF374151)),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.visibility_rounded,
                            color: Color(0xFF1565C0), size: 20),
                        tooltip: 'View',
                        onPressed: () =>
                            showEventDetailDialog(context, e),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _search = v),
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: '🔍 Search events...',
        hintStyle:
            GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon:
            const Icon(Icons.search_rounded, color: Color(0xFF1565C0)),
        suffixIcon: _search.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 20),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _search = '');
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                const BorderSide(color: Color(0xFF1565C0), width: 2)),
      ),
    );
  }

  Widget _filtersRow() {
    Widget drop({
      required String value,
      required String hint,
      required List<(String, String)> options,
      required ValueChanged<String?> onChanged,
    }) {
      return Expanded(
        child: DropdownButtonFormField<String>(
          value: value.isEmpty ? null : value,
          // Tight side-by-side rows: let long labels (e.g. "September
          // 2026") ellipsize instead of overflowing the RenderFlex.
          isExpanded: true,
          hint: Text(hint,
              style: GoogleFonts.poppins(fontSize: 12.5),
              overflow: TextOverflow.ellipsis),
          items: [
            DropdownMenuItem(
                value: '',
                child: Text('All', style: GoogleFonts.poppins(fontSize: 12.5))),
            ...options.map((o) => DropdownMenuItem(
                  value: o.$1,
                  child: Text(o.$2,
                      style: GoogleFonts.poppins(fontSize: 12.5),
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200)),
          ),
          style: GoogleFonts.poppins(
              fontSize: 12.5, color: const Color(0xFF111827)),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            drop(
              value: _filterMonth,
              hint: 'Month',
              options:
                  _monthOptions.map((m) => (m, _monthOptionLabel(m))).toList(),
              onChanged: (v) => setState(() => _filterMonth = v ?? ''),
            ),
            const SizedBox(width: 8),
            drop(
              value: _filterType,
              hint: 'Type',
              options: const [
                (EventService.typeSundaySchool, 'Sunday School'),
                (EventService.typeActivity, 'Activity'),
                (EventService.typeSpecial, 'Special'),
                (EventService.typeOthers, 'Others'),
              ],
              onChanged: (v) => setState(() => _filterType = v ?? ''),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            drop(
              value: _filterSection,
              hint: 'Section',
              options: const [
                (EventService.sectionSubJunior, 'Sub Junior'),
                (EventService.sectionJunior, 'Junior'),
                (EventService.sectionSenior, 'Senior'),
              ],
              onChanged: (v) => setState(() => _filterSection = v ?? ''),
            ),
            const SizedBox(width: 8),
            drop(
              value: _filterAudience,
              hint: 'Audience',
              options: const [
                (EventService.audienceEveryone, 'Everyone'),
                (EventService.audienceStudents, 'Students'),
                (EventService.audienceTeachers, 'Teachers'),
              ],
              onChanged: (v) => setState(() => _filterAudience = v ?? ''),
            ),
            const SizedBox(width: 8),
            drop(
              value: _filterStatus,
              hint: 'Status',
              options: const [
                (EventService.statusPublished, 'Published'),
                (EventService.statusDraft, 'Draft'),
              ],
              onChanged: (v) => setState(() => _filterStatus = v ?? ''),
            ),
          ],
        ),
      ],
    );
  }

  Widget _eventsList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF1565C0))),
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
              backgroundColor: const Color(0xFF1565C0),
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
    final items = _filtered;
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Icon(Icons.event_busy_rounded,
              size: 52, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No events found.',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151))),
          const SizedBox(height: 4),
          Text('Tap + Add Event or build a Monthly Program to begin.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade500)),
        ]),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _eventCard(items[i]),
    );
  }

  Widget _eventCard(Map<String, dynamic> event) {
    final id = (event['id'] as num?)?.toInt();
    final isEditingThis = _editingId == id && _editingId != null;
    final published = EventService.isPublished(event);
    final time = EventService.timeRangeOf(event);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
            left: BorderSide(
                color: isEditingThis
                    ? const Color(0xFF1565C0)
                    : published
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFF59E0B),
                width: 4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📅 ${(event['title'] ?? '').toString()}',
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _pill(EventService.prettyDate(event), const Color(0xFF1565C0)),
          if (time.isNotEmpty)
            _pill('🕐 $time', Colors.grey.shade600),
          _pill(EventService.prettyType(event['event_type']?.toString()),
              const Color(0xFF6D28D9)),
          _pill(
              '👥 ${EventService.prettyAudience(event['audience']?.toString())} · ${EventService.prettySections(event)}',
              const Color(0xFF7B1FA2)),
          _pill(published ? 'Published' : 'Draft',
              published ? const Color(0xFF16A34A) : Colors.grey.shade600),
        ]),
        if ((event['location'] ?? '').toString().trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('📍 ${(event['location'] ?? '').toString()}',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: const Color(0xFF374151))),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => showEventDetailDialog(context, event),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1565C0),
                side: const BorderSide(color: Color(0xFF1565C0)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text('View',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _togglePublish(event),
              style: OutlinedButton.styleFrom(
                foregroundColor: published
                    ? Colors.grey.shade700
                    : const Color(0xFF16A34A),
                side: BorderSide(
                    color: published
                        ? Colors.grey.shade400
                        : const Color(0xFF16A34A)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: Text(published ? 'Unpublish' : 'Publish',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                color: Color(0xFF1565C0), size: 20),
            tooltip: 'Edit',
            onPressed: () => _startEdit(event),
          ),
          IconButton(
            icon:
                const Icon(Icons.delete_rounded, color: Colors.red, size: 20),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(event),
          ),
        ]),
      ]),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _sheetLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF111827))),
    );
  }

  InputDecoration _sheetDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF1565C0), width: 2)),
    );
  }

  Widget _timeChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 14, color: const Color(0xFF111827))),
      ),
    );
  }
}
