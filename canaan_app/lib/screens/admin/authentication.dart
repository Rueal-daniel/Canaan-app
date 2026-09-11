import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/credential_service.dart';
import '../../services/language_service.dart';
import '../../services/password_reset_service.dart';
import '../../widgets/animations.dart';
import 'credential_requests.dart';
import 'password_reset_requests.dart';

/// Admin Dashboard → Quick Links → Authentication.
///
/// Hub for account-security sections. Holds the Password Reset
/// Requests section — tapping it opens the full request list.
class AuthenticationPage extends StatefulWidget {
  final String adminName;
  const AuthenticationPage({super.key, this.adminName = ''});

  @override
  State<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends State<AuthenticationPage> {
  final _client = Supabase.instance.client;
  int _pendingCount = 0;
  int _pendingCredCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final rows = await _client
          .from(PasswordResetService.table)
          .select('id')
          .eq('status', PasswordResetService.statusPending);
      if (mounted) setState(() => _pendingCount = (rows as List).length);
    } catch (_) {}
    try {
      final rows = await _client
          .from(CredentialService.table)
          .select('id')
          .eq('status', CredentialService.statusPending);
      if (mounted) {
        setState(() => _pendingCredCount = (rows as List).length);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
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
        title: Text(
          tr('nav_authentication'),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LangBuilder(
        builder: (_) => RefreshIndicator(
        onRefresh: _loadPending,
        color: const Color(0xFF1565C0),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('hub_acct_sec'),
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0D47A1),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr('hub_acct_sub'),
                style: GoogleFonts.poppins(
                  fontSize: 13.5,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              FadeInSlide(
                index: 0,
                child: _SectionCard(
                  icon: Icons.lock_reset_rounded,
                  title: tr('hub_pw_req'),
                  subtitle: _pendingCount > 0
                      ? trp('hub_waiting', {'n': '$_pendingCount'})
                      : tr('hub_review_recovery'),
                  badge: _pendingCount > 0 ? '$_pendingCount' : null,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B2A5B), Color(0xFF1565C0)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                          page: PasswordResetRequestsPage(
                              adminName: widget.adminName)),
                    ).then((_) => _loadPending());
                  },
                ),
              ),
              const SizedBox(height: 12),
              FadeInSlide(
                index: 1,
                child: _SectionCard(
                  icon: Icons.manage_accounts_rounded,
                  title: tr('hub_cred_req'),
                  subtitle: _pendingCredCount > 0
                      ? trp('hub_waiting', {'n': '$_pendingCredCount'})
                      : tr('hub_review_changes'),
                  badge:
                      _pendingCredCount > 0 ? '$_pendingCredCount' : null,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B1FA2), Color(0xFFAB47BC)],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      SlidePageRoute(
                          page: CredentialRequestsPage(
                              adminName: widget.adminName)),
                    ).then((_) => _loadPending());
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Gradient gradient;
  final VoidCallback onTap;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: GoogleFonts.poppins(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1A1A2E),
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(badge!,
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey.shade400,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
