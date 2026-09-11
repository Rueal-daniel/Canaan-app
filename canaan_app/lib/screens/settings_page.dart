import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/language_service.dart';

/// Sidebar → Settings (Admin / Teacher / Student).
///
/// Professional settings page. Currently hosts the Language card;
/// new preference cards belong here later. Language applies instantly
/// (no logout) and is stored per-user (device + profile row).
class SettingsPage extends StatefulWidget {
  final String role;
  final String userId;
  final String fullName;
  final List<Color>? gradient;
  const SettingsPage({
    super.key,
    required this.role,
    this.userId = '',
    this.fullName = '',
    this.gradient,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Color> get _gradient =>
      widget.gradient ??
      const [Color(0xFF0B2A5B), Color(0xFF1565C0), Color(0xFF42A5F5)];

  @override
  void initState() {
    super.initState();
    if (widget.userId.isNotEmpty) {
      LanguageService.bind(role: widget.role, userId: widget.userId);
    }
  }

  Future<void> _pick(String code) async {
    if (LanguageService.code == code) return;
    await LanguageService.setLang(
      code,
      role: widget.role,
      userId: widget.userId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('set_applied'),
            style: GoogleFonts.poppins()),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LangBuilder(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFFF4F6FB),
        appBar: AppBar(
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text(tr('set_title'),
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _headerCard(),
              const SizedBox(height: 16),
              _languageCard(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _gradient.last.withValues(alpha: 0.3),
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
          child: const Icon(Icons.settings_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('set_title'),
                    style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  widget.fullName.isEmpty
                      ? tr('set_language_sub')
                      : widget.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      color:
                          Colors.white.withValues(alpha: 0.9))),
              ]),
        ),
      ]),
    );
  }

  Widget _languageCard() {
    final code = LanguageService.code;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Text('🌐',
                    style: TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('set_language'),
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A))),
                    Text(tr('set_language_sub'),
                        style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: const Color(0xFF64748B))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _langOption(
            flag: '🇬🇧',
            label: 'English',
            value: 'en',
            selected: code == 'en',
          ),
          const SizedBox(height: 10),
          _langOption(
            flag: '🇳🇵',
            label: 'नेपाली',
            value: 'ne',
            selected: code == 'ne',
          ),
          const SizedBox(height: 14),
          Text(
            '${tr('set_current')} ${code == 'ne' ? 'नेपाली' : 'English'}',
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569)),
          ),
        ],
      ),
    );
  }

  Widget _langOption({
    required String flag,
    required String label,
    required String value,
    required bool selected,
  }) {
    return Material(
      color: selected
          ? const Color(0xFF6366F1).withValues(alpha: 0.08)
          : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _pick(value),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF6366F1)
                  : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0F172A))),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF6366F1), size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
