import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'animations.dart';

class ProfileCard extends StatelessWidget {
  final String fullName;
  final String roleBadge;
  final String? photoUrl;

  const ProfileCard({
    super.key,
    required this.fullName,
    required this.roleBadge,
    this.photoUrl,
  });

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }

  Color _getAccentColor() {
    if (roleBadge == 'Canaan Administrator') return const Color(0xFF1565C0);
    if (roleBadge == 'Teacher') return const Color(0xFF0D47A1);
    return const Color(0xFF42A5F5);
  }

  @override
  Widget build(BuildContext context) {
    final accent = _getAccentColor();
    return FadeInSlide(
      index: 0,
      duration: const Duration(milliseconds: 600),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent,
              accent.withValues(alpha: 0.85),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _buildAvatar(),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          fullName,
                          style: GoogleFonts.poppins(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.verified_rounded, color: Colors.white, size: 22),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      roleBadge,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      final fullUrl = 'https://pjytoxyddfrsrkzappbb.supabase.co/storage/v1/object/public/student-photos/$photoUrl';
      return CircleAvatar(
        radius: 32,
        backgroundColor: Colors.white.withValues(alpha: 0.2),
        backgroundImage: NetworkImage(fullUrl),
        onBackgroundImageError: (_, _) {},
        child: null,
      );
    }

    return CircleAvatar(
      radius: 32,
      backgroundColor: Colors.white.withValues(alpha: 0.2),
      child: Text(
        _getInitials(fullName),
        style: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
