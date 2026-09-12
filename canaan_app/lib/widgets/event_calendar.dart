import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/event_service.dart';

/// Shared Events & Calendar UI: month grid with red event indicators,
/// modern event cards, and the read-only detail dialog.
///
/// Used by Admin (full management), Teacher and Student (read-only).
/// Teachers/students can never create/edit/delete here — those controls
/// live only on the Admin page.

// -- month calendar ------------------------------------------------------------

/// Small modern month calendar. Dates in [eventKeys] (`yyyy-MM-dd`) get a
/// red dot indicator. Tapping a day calls [onDayTap].
class EventMonthCalendar extends StatelessWidget {
  final int year;
  final int month;
  final Set<String> eventKeys;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;
  final Color accent;
  final bool showNav;

  const EventMonthCalendar({
    super.key,
    required this.year,
    required this.month,
    required this.eventKeys,
    this.selectedDay,
    required this.onDayTap,
    this.onPrevMonth,
    this.onNextMonth,
    this.accent = const Color(0xFF1565C0),
    this.showNav = true,
  });

  @override
  Widget build(BuildContext context) {
    final days = EventService.daysInMonth(year, month);
    final lead = EventService.firstWeekday(year, month);
    final today = DateTime.now();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              if (showNav)
                _navBtn(Icons.chevron_left_rounded, onPrevMonth)
              else
                const SizedBox(width: 36),
              Expanded(
                child: Text(
                  EventService.monthLabel(year, month),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              if (showNav)
                _navBtn(Icons.chevron_right_rounded, onNextMonth)
              else
                const SizedBox(width: 36),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final w in EventService.weekdaysShort)
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.92,
            ),
            itemCount: lead + days,
            itemBuilder: (_, i) {
              if (i < lead) return const SizedBox.shrink();
              final day = i - lead + 1;
              final date = DateTime(year, month, day);
              final key = EventService.dateKey(date);
              final hasEvent = eventKeys.contains(key);
              final isSelected = selectedDay != null &&
                  EventService.sameDay(selectedDay!, date);
              final isToday = EventService.sameDay(today, date);
              return GestureDetector(
                onTap: () => onDayTap(date),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withValues(alpha: 0.14)
                        : isToday
                            ? const Color(0xFFF1F5F9)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(color: accent, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? accent
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasEvent
                              ? const Color(0xFFEF4444)
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Event date',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: accent),
      ),
    );
  }
}

// -- event cards -----------------------------------------------------------------

/// Modern upcoming-event card (teacher/student list).
class EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;
  final Color accent;

  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.accent = const Color(0xFF1565C0),
  });

  @override
  Widget build(BuildContext context) {
    final title = (event['title'] ?? 'Event').toString();
    final time = EventService.timeRangeOf(event);
    final location = (event['location'] ?? '').toString().trim();
    final sections = EventService.prettySections(event);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: const Border(
            left: BorderSide(color: Color(0xFFEF4444), width: 4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    EventService.iconFor(event['event_type']?.toString()),
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line(Icons.calendar_month_rounded, EventService.prettyDate(event)),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 5),
              _line(Icons.access_time_rounded, time),
            ],
            if (location.isNotEmpty) ...[
              const SizedBox(height: 5),
              _line(Icons.place_rounded, location),
            ],
            const SizedBox(height: 5),
            _line(Icons.group_rounded, sections),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'View Details →',
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF374151),
            ),
          ),
        ),
      ],
    );
  }
}

// -- detail dialog ------------------------------------------------------------------

/// Read-only detail sheet shared by Admin/Teacher/Student.
void showEventDetailDialog(
  BuildContext context,
  Map<String, dynamic> event, {
  Color accent = const Color(0xFF1565C0),
}) {
  final title = (event['title'] ?? 'Event').toString();
  final time = EventService.timeRangeOf(event);
  final location = (event['location'] ?? '').toString().trim();
  final description = (event['description'] ?? '').toString().trim();
  final attachmentUrl = (event['attachment_url'] ?? '').toString().trim();
  final attachmentName = (event['attachment_name'] ?? '').toString().trim();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              EventService.iconFor(event['event_type']?.toString()),
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 16.5,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(EventService.prettyType(event['event_type']?.toString()),
                    accent),
                _pill(
                    EventService.prettyAudience(
                        event['audience']?.toString()),
                    const Color(0xFF7B1FA2)),
              ],
            ),
            const SizedBox(height: 14),
            _detail('📅', EventService.prettyDate(event)),
            if (time.isNotEmpty) _detail('🕐', time),
            if (location.isNotEmpty) _detail('📍', location),
            _detail('👥', EventService.prettySections(event)),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '📝 Description',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  height: 1.6,
                  color: const Color(0xFF374151),
                ),
              ),
            ],
            if (attachmentUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  try {
                    final uri = Uri.parse(attachmentUrl);
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  } catch (_) {}
                },
                child: Row(
                  children: [
                    const Icon(Icons.attach_file_rounded,
                        size: 16, color: Color(0xFF1565C0)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        attachmentName.isNotEmpty
                            ? '📎 $attachmentName'
                            : '📎 Open attachment',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1565C0),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Close',
              style: GoogleFonts.poppins(color: Colors.grey.shade600)),
        ),
      ],
    ),
  );
}

Widget _detail(String emoji, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      '$emoji $text',
      style: GoogleFonts.poppins(
        fontSize: 13.5,
        color: const Color(0xFF374151),
      ),
    ),
  );
}

Widget _pill(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );
}
