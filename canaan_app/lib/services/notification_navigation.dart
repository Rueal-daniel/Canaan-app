import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/notification_service.dart';
import '../widgets/animations.dart';
import '../screens/admin/authentication.dart';
import '../screens/admin/credential_requests.dart';
import '../screens/admin/download_center.dart';
import '../screens/admin/leave_applications.dart';
import '../screens/admin/lesson_plan.dart';
import '../screens/admin/notice_board.dart';
import '../screens/admin/password_reset_requests.dart';
import '../screens/admin/std_report.dart';
import '../screens/admin/student_applications.dart';
import '../screens/change_credentials_page.dart';
import '../screens/student/download_center.dart';
import '../screens/student/leave_application.dart';
import '../screens/student/memory_verse.dart';
import '../screens/student/my_attendance.dart';
import '../screens/student/notice_board.dart';
import '../screens/teacher/download_center.dart';
import '../screens/teacher/lesson_plan.dart';
import '../screens/teacher/memory_verse.dart';
import '../screens/teacher/my_attendance.dart';
import '../screens/teacher/notice_board.dart';
import '../screens/teacher/student_applications.dart';

/// Resolves a notification's [destination] key to the EXISTING
/// dashboard page for the current role. No duplicate pages are created:
/// every branch pushes a page that already exists in the app.
///
/// The notification is always marked read BEFORE this runs (the bell
/// handles that), so this helper only navigates.
class NotificationNavigation {
  static Future<void> handleTap(
    BuildContext context, {
    required String role,
    required AppNotification notification,
    String fullName = '',
    String? section,
    String teacherId = '',
    String teacherName = '',
    String adminName = '',
  }) async {
    final r = role.trim().toLowerCase();
    final name = fullName.trim().isEmpty ? teacherName : fullName;
    final sec = (section ?? '').trim();
    final tid = teacherId.trim();
    final tname = teacherName.trim().isEmpty ? name : teacherName.trim();
    final aname = adminName.trim().isEmpty ? name : adminName.trim();

    Widget? page;
    switch (notification.destination) {
      case NotificationService.destAttendance:
        if (r == 'student') {
          page = MyAttendance(fullName: name);
        }
        break;
      case NotificationService.destMyAttendance:
        if (tid.isEmpty) {
          _deny(context, 'Could not identify teacher account');
          return;
        }
        page = TeacherMyAttendance(teacherId: tid, section: sec);
        break;
      case NotificationService.destNoticeBoard:
        if (r == 'student') {
          page = StudentNoticeBoardPage(studentName: name);
        } else if (r == 'teacher') {
          page = TeacherNoticeBoardPage(teacherId: tid, teacherName: tname);
        } else {
          page = AdminNoticeBoardPage(adminName: aname);
        }
        break;
      case NotificationService.destLeaveApplication:
        if (r == 'student') {
          page = StudentLeaveApplicationPage(fullName: name, section: sec);
        } else if (r == 'teacher') {
          if (sec.isEmpty) {
            _deny(context, 'No section assigned yet');
            return;
          }
          page = TeacherStudentApplicationsPage(section: sec);
        } else {
          page = AdminLeaveApplicationsPage(adminName: aname);
        }
        break;
      case NotificationService.destStudentApplications:
        if (r == 'teacher') {
          if (sec.isEmpty) {
            _deny(context, 'No section assigned yet');
            return;
          }
          page = TeacherStudentApplicationsPage(section: sec);
        } else if (r == 'admin') {
          page = const AdminStudentApplicationsPage();
        } else {
          page = StudentLeaveApplicationPage(fullName: name, section: sec);
        }
        break;
      case NotificationService.destStudentReports:
        if (r == 'admin') {
          page = const StdReport();
        } else {
          page = AuthenticationPage(adminName: aname);
        }
        break;
      case NotificationService.destLessonPlan:
        if (r == 'teacher') {
          if (sec.isEmpty) {
            _deny(context, 'No section assigned yet');
            return;
          }
          page = TeacherLessonPlanPage(
            section: sec,
            teacherId: tid,
            teacherName: tname,
          );
        } else if (r == 'admin') {
          page = AdminLessonPlanPage(adminName: aname);
        } else {
          // Students have no dedicated lesson-plan page; the teacher
          // plan page is read-only, so it is reused (no duplicate page).
          if (sec.isEmpty) {
            _deny(context, 'No section assigned yet');
            return;
          }
          page = TeacherLessonPlanPage(section: sec);
        }
        break;
      case NotificationService.destMemoryVerse:
        if (sec.isEmpty) {
          _deny(context, 'No section assigned yet');
          return;
        }
        if (r == 'student') {
          page = StudentMemoryVerse(section: sec);
        } else {
          page = TeacherMemoryVerse(
            teacherId: tid,
            teacherName: tname,
            section: sec,
          );
        }
        break;
      case NotificationService.destCredentials:
        if (r == 'admin') {
          page = CredentialRequestsPage(adminName: aname);
        } else {
          page = ChangeCredentialsPage(role: r, fullName: name);
        }
        break;
      case NotificationService.destCredentialsAdmin:
        page = CredentialRequestsPage(adminName: aname);
        break;
      case NotificationService.destPasswordResetAdmin:
        page = PasswordResetRequestsPage(adminName: aname);
        break;
      case NotificationService.destDownloadCenter:
        if (r == 'student') {
          page = const StudentDownloadCenterPage();
        } else if (r == 'teacher') {
          page = const TeacherDownloadCenterPage();
        } else {
          page = AdminDownloadCenterPage(adminName: aname);
        }
        break;
      default:
        // dashboard / website_update / unknown: already marked read,
        // nothing further to open.
        return;
    }
    if (page == null || !context.mounted) return;
    await Navigator.push(context, SlidePageRoute(page: page));
  }

  static void _deny(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins()),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
