import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/linked_student_service.dart';

/// "Switch Student" bottom sheet: shows every Admin-linked student with
/// photo (initials fallback), name, section and a "Current" indicator.
///
/// Selecting a student does NOT log out and never asks for credentials —
/// the caller re-verifies the choice on the server and swaps the active
/// dashboard instantly.
class SwitchStudentSheet extends StatefulWidget {
  /// The secure login (authenticated) student id — used for server
  /// verification. Never the password, never a fake session.
  final String loginStudentId;

  /// Currently active student id (shows the ✓ Current badge).
  final String activeStudentId;

  const SwitchStudentSheet({
    super.key,
    required this.loginStudentId,
    required this.activeStudentId,
  });

  @override
  State<SwitchStudentSheet> createState() => _SwitchStudentSheetState();
}

class _SwitchStudentSheetState extends State<SwitchStudentSheet> {
  List<Map<String, dynamic>> _linked = [];
  bool _isLoading = true;
  String? _switchingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await LinkedStudentService.fetchLinkedStudents(
        widget.loginStudentId);
    if (!mounted) return;
    setState(() {
      _linked = rows;
      _isLoading = false;
    });
  }

  Future<void> _choose(Map<String, dynamic> student) async {
    final targetId = (student['id'] ?? '').toString();
    if (targetId.isEmpty || _switchingId != null) return;
    if (targetId == widget.activeStudentId) {
      Navigator.pop(context);
      return;
    }
    final suspended =
        (student['status'] ?? '').toString().trim().toLowerCase() ==
            'suspended';
    if (suspended) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'This account is suspended. Please contact the Admin.',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    setState(() => _switchingId = targetId);
    // Server re-verification: only a provably-linked, existing,
    // non-suspended student is returned (§11).
    final row = await LinkedStudentService.verifyAndSwitch(
      loginStudentId: widget.loginStudentId,
      targetId: targetId,
    );
    if (!mounted) return;
    if (row == null) {
      setState(() => _switchingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switch not allowed for this account.',
              style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      await _load();
      return;
    }
    // Return the verified row so the dashboard swaps instantly.
    Navigator.pop(context, row);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF4F6FB),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xFF063B2E),
                    Color(0xFF0E9F6E),
                  ]),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.switch_account_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Linked Students',
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A))),
                      Text('Tap a profile to switch instantly — no login needed.',
                          style: GoogleFonts.poppins(
                              fontSize: 12.5,
                              color: const Color(0xFF64748B))),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF0E9F6E)))
                  : _linked.length < 2
                      ? Center(
                          child: Text(
                              'No linked students found.\nAsk the Admin to link your family accounts.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey.shade500)),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _linked.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) =>
                              _tile(_linked[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> student) {
    final id = (student['id'] ?? '').toString();
    final isCurrent = id == widget.activeStudentId;
    final isBusy = _switchingId == id;
    final photo = LinkedStudentService.photoUrlOf(student);
    final name = ((student['full_name'] ?? '').toString().trim().isEmpty)
        ? (student['username'] ?? 'Student').toString()
        : (student['full_name'] ?? '').toString();
    final section = LinkedStudentService.prettySection(
        (student['section'] ?? '').toString());
    final studentNo =
        (student['student_id_number'] ?? '').toString().trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _choose(student),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: isCurrent
                    ? const Color(0xFF0E9F6E)
                    : const Color(0xFFE8EEF6),
                width: isCurrent ? 1.5 : 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFF0E9F6E)
                      .withValues(alpha: 0.12),
                  backgroundImage:
                      photo.isNotEmpty ? NetworkImage(photo) : null,
                  onBackgroundImageError:
                      photo.isNotEmpty ? (_, _) {} : null,
                  child: photo.isEmpty
                      ? Text(
                          LinkedStudentService.initialsOf(name),
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0E9F6E)),
                        )
                      : null,
                ),
                if (isCurrent)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0E9F6E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 12, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A))),
                    const SizedBox(height: 3),
                    Row(children: [
                      Flexible(
                        child: Text(
                            section.isEmpty ? 'Student' : section,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 12.5,
                                color: const Color(0xFF64748B))),
                      ),
                      if (studentNo.isNotEmpty)
                        Flexible(
                          child: Text('  •  $studentNo',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: const Color(0xFF94A3B8))),
                        ),
                    ]),
                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E9F6E)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('✓ Current Student',
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0E9F6E))),
                        ),
                      ),
                  ]),
            ),
            if (isBusy)
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    color: Color(0xFF0E9F6E), strokeWidth: 2.5),
              )
            else if (!isCurrent)
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 17, color: Color(0xFF0E9F6E)),
          ]),
        ),
      ),
    );
  }
}

/// Opens the switch sheet and returns the verified target row (or null).
Future<Map<String, dynamic>?> showSwitchStudentSheet(
  BuildContext context, {
  required String loginStudentId,
  required String activeStudentId,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SwitchStudentSheet(
      loginStudentId: loginStudentId,
      activeStudentId: activeStudentId,
    ),
  );
}
