import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/student_update_service.dart';

/// Shared student-report detail view used by Admin history ("View") and
/// the student's My Update page. Read-only.
void showStudentUpdateDetail(
  BuildContext context,
  Map<String, dynamic> update, {
  Color accent = const Color(0xFF1565C0),
}) {
  final parts =
      StudentUpdateService.splitDetail((update['behaviour_detail'] ?? '').toString());
  final did = parts.$1;
  final learned = parts.$2;
  final behaviour = parts.$3;
  final notes = (update['additional_notes'] ?? '').toString().trim();
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
            child: Text('📋', style: GoogleFonts.poppins(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Student Update',
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
            _row('📅 Date', StudentUpdateService.prettyDate(update)),
            _row('👤 Student Name',
                (update['student_name'] ?? '').toString()),
            _row('🆔 Student ID',
                (update['student_id'] ?? '').toString()),
            _row('👥 Section',
                StudentUpdateService.prettySection(
                    update['section']?.toString())),
            FutureBuilder<String>(
              future: StudentUpdateService.teacherNamesFor(
                  Supabase.instance.client,
                  update['section']?.toString()),
              builder: (_, snap) {
                final names = (snap.data ?? '').trim();
                if (names.isEmpty) return const SizedBox.shrink();
                return _row('👨‍🏫 Teacher', names);
              },
            ),
            const SizedBox(height: 10),
            if (did.isNotEmpty) ...[
              _sectionTitle('What Did the Student Do Today?'),
              _body(did),
            ],
            if (learned.isNotEmpty) ...[
              _sectionTitle('What Did the Student Learn?'),
              _body(learned),
            ],
            if (behaviour.isNotEmpty) ...[
              _sectionTitle('Behaviour Description'),
              _body(behaviour),
            ],
            const SizedBox(height: 6),
            _row('⭐ Saturday Rating',
                StudentUpdateService.starsLabel(
                    StudentUpdateService.ratingOf(update))),
            _row('📊 Student Percentage',
                '${StudentUpdateService.percentageOf(update)}%'),
            if (notes.isNotEmpty) ...[
              _sectionTitle('Additional Notes'),
              _body(notes),
            ],
            const SizedBox(height: 6),
            _row('✅ Updated By',
                (update['created_by'] ?? '').toString().trim().isEmpty
                    ? 'Canaan Administrator'
                    : (update['created_by'] ?? '').toString()),
            _row('🕐 Created',
                (update['created_at'] ?? '').toString().split('.').first.replaceAll('T', ' ')),
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

Widget _row(String label, String value) {
  if (value.trim().isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: RichText(
      text: TextSpan(
        style: GoogleFonts.poppins(
            fontSize: 13.5, color: const Color(0xFF374151)),
        children: [
          TextSpan(
            text: '$label: ',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}

Widget _sectionTitle(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF111827),
      ),
    ),
  );
}

Widget _body(String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13.5,
        height: 1.6,
        color: const Color(0xFF374151),
      ),
    ),
  );
}
