import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/notification_service.dart';
import '../services/prayer_request_service.dart';
import '../screens/app_update_popup.dart';
import '../widgets/animations.dart';
import '../screens/admin/authentication.dart';
import '../screens/admin/alerts.dart';
import '../screens/admin/certificates.dart';
import '../screens/admin/complaints.dart';
import '../screens/admin/credential_requests.dart';
import '../screens/admin/download_center.dart';
import '../screens/admin/events_calendar.dart';
import '../screens/admin/prayer_requests.dart';
import '../screens/admin/school_gallery.dart';
import '../screens/admin/student_update.dart';
import '../screens/admin/leave_applications.dart';
import '../screens/admin/lesson_plan.dart';
import '../screens/admin/notice_board.dart';
import '../screens/admin/password_reset_requests.dart';
import '../screens/admin/std_report.dart';
import '../screens/admin/student_applications.dart';
import '../screens/change_credentials_page.dart';
import '../screens/student/download_center.dart';
import '../screens/student/events_calendar.dart';
import '../screens/student/canaan_gallery.dart';
import '../screens/student/alerts.dart';
import '../screens/student/certificates.dart';
import '../screens/student/my_update.dart';
import '../screens/student/prayer_requests.dart';
import '../screens/student/leave_application.dart';
import '../screens/student/memory_verse.dart';
import '../screens/student/my_attendance.dart';
import '../screens/student/notice_board.dart';
import '../screens/teacher/download_center.dart';
import '../screens/teacher/events_calendar.dart';
import '../screens/teacher/canaan_gallery.dart';
import '../screens/teacher/alerts.dart';
import '../screens/teacher/certificates.dart';
import '../screens/teacher/prayer_requests.dart';
import '../screens/teacher/lesson_plan.dart';
import '../screens/teacher/memory_verse.dart';
import '../screens/teacher/my_attendance.dart';
import '../screens/teacher/notice_board.dart';
import '../screens/teacher/student_applications.dart';
import '../screens/teacher/teacher_tasks.dart';
import '../screens/admin/teacher_tasks.dart';

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
      case NotificationService.destTeacherTasks:
        if (r == 'teacher') {
          if (tid.isEmpty) {
            _deny(context, 'Could not identify teacher account');
            return;
          }
          page = TeacherTasksPage(
            teacherId: tid,
            teacherName: tname,
            section: sec,
          );
        }
        break;
      case NotificationService.destTeacherTasksAdmin:
        if (r == 'admin') {
          page = AdminTeacherTasksPage(adminName: aname);
        }
        break;
      case NotificationService.destEventsCalendar:
        if (r == 'student') {
          page = StudentEventsCalendarPage(
            studentName: name,
            section: sec,
          );
        } else if (r == 'teacher') {
          page = TeacherEventsCalendarPage(
            teacherId: tid,
            teacherName: tname,
            section: sec,
          );
        } else {
          page = AdminEventsCalendarPage(adminName: aname);
        }
        break;
      case NotificationService.destGallery:
        if (r == 'student') {
          page = StudentCanaanGalleryPage(
            studentName: name,
            section: sec,
          );
        } else if (r == 'teacher') {
          page = TeacherCanaanGalleryPage(
            teacherId: tid,
            teacherName: tname,
            section: sec,
          );
        } else {
          page = AdminSchoolGalleryPage(adminName: aname);
        }
        break;
      case NotificationService.destPrayerRequests:
        final focusId =
            PrayerRequestService.focusIdFromRelatedId(
                notification.relatedId);
        if (r == 'student') {
          page = StudentPrayerRequestPage(
            studentName: name,
            focusRequestId: focusId,
          );
        } else if (r == 'teacher') {
          page = TeacherPrayerRequestPage(
            teacherId: tid,
            teacherName: tname,
            focusRequestId: focusId,
          );
        } else {
          page = AdminPrayerRequestPage(
            adminName: aname,
            focusRequestId: focusId,
          );
        }
        break;
      case NotificationService.destMyUpdate:
        if (r == 'student') {
          page = StudentMyUpdatePage(
            fullName: name,
            section: sec.isEmpty ? null : sec,
          );
        } else {
          page = AdminStudentUpdatePage(adminName: aname);
        }
        break;
      case NotificationService.destCertificates:
        if (r == 'student') {
          page = StudentCertificatesPage(studentName: name);
        } else if (r == 'teacher') {
          page = TeacherCertificatesPage(
            teacherId: tid,
            teacherName: tname,
          );
        } else {
          page = const AdminCertificatesPage();
        }
        break;
      case NotificationService.destAlerts:
        if (r == 'student') {
          page = StudentAlertsPage(studentName: name);
        } else if (r == 'teacher') {
          page = TeacherAlertsPage(
            teacherId: tid,
            teacherName: tname,
          );
        } else {
          page = AdminAlertsPage(adminName: aname);
        }
        break;
      case NotificationService.destComplaints:
        // Only admins ever receive complaint notifications.
        if (r == 'admin') {
          page = AdminComplaintsPage(adminName: aname);
        } else {
          return;
        }
        break;
      case NotificationService.destAppUpdate:
        // Update popup for every role (only shows when the published
        // versionCode exceeds the installed one, otherwise confirms).
        await showAppUpdateIfAvailable(context, announceUpToDate: true);
        return;
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
