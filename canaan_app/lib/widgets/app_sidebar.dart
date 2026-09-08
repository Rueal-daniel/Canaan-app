import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'about_canaan.dart';
import '../screens/change_credentials_page.dart';
import '../screens/profile_page.dart';
import 'dashboard_design.dart' show dashInitials;

/// Common dashboard drawer for Admin / Teacher / Student.
///
/// Holds ONLY the profile box on top and the About Canaan button —
/// no navigation items. The dashboard body behind it is left
/// completely untouched.
class CanaanSidebar extends StatelessWidget {
  final List<Color> gradient;
  final String fullName;
  final String roleLabel;

  /// 'admin' | 'teacher' | 'student' — decides which table the
  /// Profile button loads.
  final String role;
  final String? photoUrl;
  const CanaanSidebar({
    super.key,
    required this.gradient,
    required this.fullName,
    required this.roleLabel,
    required this.role,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF4F6FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // -- modern rounded profile box ----------------------------------
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: gradient.last.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        Colors.white.withValues(alpha: 0.2),
                    backgroundImage:
                        photoUrl != null && photoUrl!.isNotEmpty
                            ? NetworkImage(photoUrl!)
                            : null,
                    onBackgroundImageError:
                        photoUrl != null && photoUrl!.isNotEmpty
                            ? (_, _) {}
                            : null,
                    child: photoUrl == null || photoUrl!.isEmpty
                        ? Text(dashInitials(fullName),
                            style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.25)),
                          ),
                          child: Text(roleLabel,
                              style: GoogleFonts.poppins(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ),
                      ]),
                ),
              ]),
            ),
            // -- About Canaan, right below the profile box --------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _SidebarButton(
                icon: Icons.church_rounded,
                label: 'About Canaan',
                gradient: const [Color(0xFF0B2A5B), Color(0xFF1565C0)],
                onTap: () {
                  Navigator.pop(context);
                  showAboutCanaan(context);
                },
              ),
            ),
            // -- Profile: this person's full details ---------------------------
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _SidebarButton(
                icon: Icons.person_rounded,
                label: 'Profile',
                gradient: const [Color(0xFF065F46), Color(0xFF10B981)],
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfilePage(
                        role: role,
                        fallbackName: fullName,
                        photoUrl: photoUrl,
                      ),
                    ),
                  );
                },
              ),
            ),
            // -- Change Credentials (teacher & student only) --------------------
            if (role == 'teacher' || role == 'student')
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: _SidebarButton(
                  icon: Icons.manage_accounts_rounded,
                  label: 'Change Credentials',
                  gradient: const [Color(0xFFB45309), Color(0xFFF59E0B)],
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChangeCredentialsPage(
                          role: role,
                          fullName: fullName,
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// Gradient action button with press feedback, used for About Canaan
/// and Profile.
class _SidebarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;
  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onHover: (v) => setState(() => _pressed = v),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: widget.gradient),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: widget.gradient.last.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(widget.label,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ]),
          ),
        ),
      ),
    );
  }
}
