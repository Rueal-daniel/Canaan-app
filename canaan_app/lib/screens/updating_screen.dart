import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_update_service.dart';

/// Real APK download with byte-accurate progress, then handoff to the
/// Android system installer. Cancel is offered for optional updates.
class UpdatingScreen extends StatefulWidget {
  final RemoteUpdate update;
  const UpdatingScreen({super.key, required this.update});

  @override
  State<UpdatingScreen> createState() => _UpdatingScreenState();
}

class _UpdatingScreenState extends State<UpdatingScreen> {
  Completer<void> _cancelToken = Completer<void>();
  DownloadProgress? _progress;
  String? _error;
  bool _installing = false;
  File? _apkFile;

  @override
  void initState() {
    super.initState();
    _downloadAndInstall();
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _error = null;
      _installing = false;
      _progress = null;
      _apkFile = null;
    });
    try {
      final file = await AppUpdateService.downloadApk(
        widget.update,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
        cancelToken: _cancelToken,
      );
      if (!mounted) return;
      setState(() {
        _apkFile = file;
        _installing = true;
      });
      final err = await AppUpdateService.installApk(file);
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _installing = false;
          _error = err;
        });
      }
      // Success: Android's installer is now in charge.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _openInstallerAgain() async {
    final file = _apkFile;
    if (file == null) return;
    final err = await AppUpdateService.installApk(file);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
    }
  }

  void _retry() {
    if (_cancelToken.isCompleted) _cancelToken = Completer<void>();
    _downloadAndInstall();
  }

  void _cancel() {
    if (!_cancelToken.isCompleted) _cancelToken.complete();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (!_cancelToken.isCompleted) _cancelToken.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final pct = _progress?.fraction;

    return PopScope(
      canPop: !u.forceUpdate,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !u.forceUpdate) {
          AppUpdateService.markSkipped(u.versionCode);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F5F9),
        appBar: AppBar(
          elevation: 0,
          automaticallyImplyLeading: !u.forceUpdate,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text('Downloading Update',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _heroCard(),
              const SizedBox(height: 20),
              if (_error != null)
                _errorCard()
              else if (_installing)
                _installingCard()
              else
                _progressCard(pct),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.3),
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
          child: const Icon(Icons.system_update_rounded,
              color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.update.updateTitle,
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 4),
              Text('Version ${widget.update.versionName}',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9))),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _progressCard(double? pct) {
    final received = _progress?.received ?? 0;
    final total = _progress?.total;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Downloading Update…',
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827))),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 12,
            child: pct == null
                ? const LinearProgressIndicator(
                    color: Color(0xFF1565C0),
                    backgroundColor: Color(0xFFF1F5F9),
                  )
                : LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    color: const Color(0xFF1565C0),
                    backgroundColor: const Color(0xFFF1F5F9),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
              total != null
                  ? 'Downloaded: ${AppUpdateService.formatMB(received)} MB / ${AppUpdateService.formatMB(total)} MB'
                  : 'Downloaded: ${AppUpdateService.formatMB(received)} MB',
              style: GoogleFonts.poppins(
                  fontSize: 12.5, color: Colors.grey.shade600)),
          if (pct != null)
            Text('${(pct * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1565C0))),
        ]),
        if (!widget.update.forceUpdate) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_rounded, size: 18),
              label: Text('Cancel',
                  style:
                      GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFEF4444)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _installingCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF063B2E), Color(0xFF0E9F6E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E9F6E).withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: [
        const SizedBox(
          height: 44,
          width: 44,
          child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 3),
        ),
        const SizedBox(height: 14),
        Text('Opening Android Installer…',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        const SizedBox(height: 6),
        Text('Tap "Install" on the system dialog to update Canaan.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.9))),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: _openInstallerAgain,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Open Installer Again',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _errorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFEF4444), size: 22),
          const SizedBox(width: 10),
          Text('Download Failed',
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFEF4444))),
        ]),
        const SizedBox(height: 8),
        Text(_error ?? 'Something went wrong.',
            style: GoogleFonts.poppins(
                fontSize: 13, color: Colors.grey.shade700)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('Retry',
                    style:
                        GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
          if (!widget.update.forceUpdate) ...[
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}
