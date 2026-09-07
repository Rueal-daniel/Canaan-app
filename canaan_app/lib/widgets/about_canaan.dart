import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

/// About Canaan — identical on Admin / Teacher / Student dashboards.
///
/// Shows the existing Canaan logo, school name, tappable contact
/// boxes (email → mail app, phone → dialer, website → browser)
/// and the family thank-you closing message.
Future<void> showAboutCanaan(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FB),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1565C0)
                          .withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'images/canaan logo.png',
                    width: 110,
                    height: 110,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.church_rounded,
                        size: 64,
                        color: Color(0xFF1565C0)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Canaan Sunday School',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                      letterSpacing: 0.2)),
              const SizedBox(height: 4),
              Text('Learn • Grow • Serve',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF64748B),
                      letterSpacing: 1.5)),
              const SizedBox(height: 22),
              _ContactBox(
                icon: Icons.mail_rounded,
                label: 'Email',
                value: 'canaansschool@gmail.com',
                color: const Color(0xFF1565C0),
                onTap: () => _launch(
                    ctx, Uri.parse('mailto:canaansschool@gmail.com')),
              ),
              const SizedBox(height: 12),
              _ContactBox(
                icon: Icons.phone_rounded,
                label: 'Phone',
                value: '01-4792902',
                color: const Color(0xFF22C55E),
                onTap: () =>
                    _launch(ctx, Uri.parse('tel:014792902')),
              ),
              const SizedBox(height: 12),
              _ContactBox(
                icon: Icons.language_rounded,
                label: 'Website',
                value: 'canaan-ss.site.je',
                color: const Color(0xFF7B1FA2),
                onTap: () => _launch(
                    ctx, Uri.parse('https://canaan-ss.site.je'),
                    newTab: true),
              ),
              const SizedBox(height: 26),
              Text('Thank you for being part of the Canaan Sunday School Family. ❤️',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      height: 1.6,
                      color: const Color(0xFF64748B))),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _launch(BuildContext context, Uri uri,
    {bool newTab = false}) async {
  try {
    final ok = await launchUrl(
      uri,
      mode: newTab
          ? LaunchMode.externalApplication
          : LaunchMode.platformDefault,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open link.',
            style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open link.',
            style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }
}

class _ContactBox extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;
  const _ContactBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ContactBox> createState() => _ContactBoxState();
}

class _ContactBoxState extends State<_ContactBox> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _pressed ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: widget.color.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  widget.color,
                  widget.color.withValues(alpha: 0.75)
                ]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: GoogleFonts.poppins(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF64748B))),
                    const SizedBox(height: 1),
                    Text(widget.value,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A))),
                  ]),
            ),
            Icon(Icons.open_in_new_rounded,
                size: 18, color: widget.color.withValues(alpha: 0.7)),
          ]),
        ),
      ),
    );
  }
}
