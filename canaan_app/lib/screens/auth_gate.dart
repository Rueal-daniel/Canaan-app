import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../widgets/animations.dart';
import 'admin/admin_dashboard.dart';
import 'login_screen.dart';
import 'student/student_dashboard.dart';
import 'teacher/teacher_dashboard.dart';

/// First screen of the app.
///
/// Restores the Supabase login session (persistent across app close,
/// Android "Close all", and restarts) BEFORE deciding what to show, so
/// the Login page never flashes while the session is being checked.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _restoreAndRoute();
  }

  Future<void> _restoreAndRoute() async {
    try {
      final restored = await _authService.restoreSession();
      if (!mounted) return;

      if (restored == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }

      final user = restored.user;
      Widget dashboard;
      switch (restored.role) {
        case UserRole.admin:
          dashboard = AdminDashboard(
            fullName: user['full_name'] ?? user['username'] ?? 'Admin',
          );
          break;
        case UserRole.teacher:
          dashboard = TeacherDashboard(
            fullName: user['full_name'] ?? user['username'] ?? 'Teacher',
            username: user['username'],
            section: user['section'],
          );
          break;
      case UserRole.student:
        dashboard = StudentDashboard(
          fullName: user['full_name'] ?? user['username'] ?? 'Student',
          photoUrl: user['photo_url'],
          section: user['section'],
        );
        break;
      }

      if (!mounted) return;
      Navigator.pushReplacement(context, SlidePageRoute(page: dashboard));
    } on AccountSuspendedException {
      // A previously logged-in student was suspended: session already
      // cleared — land on Login with the suspension notice.
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(suspendedNotice: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading Canaan…',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(color: Color(0xFF1565C0)),
          ],
        ),
      ),
    );
  }
}
