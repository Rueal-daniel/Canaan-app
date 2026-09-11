import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/language_service.dart';

/// Shared 5-star rating widgets for the Student Progress system.
///
/// Stars are outline (empty) when not awarded and filled amber when the
/// Admin gives the rating. The rating is ALWAYS the Admin's manual
/// overall assessment — never auto-converted from percentages.
class StarRating extends StatelessWidget {
  /// 0..5 (0 = unrated, all outline).
  final int stars;
  final double size;
  final Color fillColor;
  const StarRating({
    super.key,
    required this.stars,
    this.size = 22,
    this.fillColor = const Color(0xFFF59E0B),
  });

  @override
  Widget build(BuildContext context) {
    final value = stars.clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= value ? fillColor : Colors.grey.shade400,
          ),
      ],
    );
  }
}

/// Interactive star picker for the Admin evaluation screen. Starts all
/// outline (☆☆☆☆☆); tapping a star awards up to it; tapping the
/// currently-selected star clears back to 0.
class StarPicker extends StatelessWidget {
  final int stars;
  final ValueChanged<int> onChanged;
  final double size;
  const StarPicker({
    super.key,
    required this.stars,
    required this.onChanged,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    final value = stars.clamp(0, 5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () => onChanged(i == value ? 0 : i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                i <= value
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: size,
                color: i <= value
                    ? const Color(0xFFF59E0B)
                    : Colors.grey.shade400,
              ),
            ),
          ),
      ],
    );
  }
}

/// `4.0 / 5` caption under a star row.
class StarCaption extends StatelessWidget {
  final int stars;
  const StarCaption({super.key, required this.stars});

  @override
  Widget build(BuildContext context) {
    final value = stars.clamp(0, 5);
    return Text(
      value == 0 ? tr('pg_not_rated') : '$value.0 / 5',
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF64748B),
      ),
    );
  }
}
