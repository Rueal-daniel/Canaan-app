import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/notice_service.dart';

/// No-package rich-text system for the Notice Board.
///
/// What-you-see-is-what-you-get composer: formatting (bold, italic,
/// colors, sizes, bullets…) renders live inside the typing area via a
/// custom [TextEditingController], and serialises to an HTML subset
/// saved in `notices.content`. [NoticeContentView] renders that same
/// HTML everywhere so formatting is always preserved.
///
/// Supported: bold, italic, underline, strikethrough, text size
/// (Small / Normal / Large / Headings), text color, highlight,
/// align left / center / right / justify, bullet + numbered lists,
/// undo, redo, clear formatting.
class NoticeContentView extends StatelessWidget {
  final String html;
  final double baseSize;
  const NoticeContentView(this.html, {super.key, this.baseSize = 14.5});

  @override
  Widget build(BuildContext context) {
    final lines = _parseNoticeHtml(html);
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < lines.length; i++) ...[
          _blockWidget(lines[i]),
          if (i < lines.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _blockWidget(_Line line) {
    final runs = _computeRuns(line, baseSize);
    final span = TextSpan(
      children: [
        for (final r in runs)
          TextSpan(
            text: line.text.substring(r.start, r.end),
            style: GoogleFonts.poppins(
              fontSize: r.fontSize,
              fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
              color: r.color,
              backgroundColor: r.bg,
              decoration: r.underline && r.strike
                  ? TextDecoration.combine([
                      TextDecoration.underline,
                      TextDecoration.lineThrough
                    ])
                  : r.underline
                      ? TextDecoration.underline
                      : r.strike
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
            ),
          ),
        if (line.text.isEmpty) const TextSpan(text: ''),
      ],
      style: GoogleFonts.poppins(
          fontSize: baseSize, color: const Color(0xFF1F2937), height: 1.6),
    );
    final text = RichText(
      textAlign: _alignOf(line.align),
      text: span,
    );
    if (line.block == _Block.bullet) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ',
              style: GoogleFonts.poppins(
                  fontSize: baseSize,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937),
                  height: 1.6)),
          Expanded(child: text),
        ],
      );
    }
    if (line.block == _Block.number) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${line.number}.  ',
              style: GoogleFonts.poppins(
                  fontSize: baseSize,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937),
                  height: 1.6)),
          Expanded(child: text),
        ],
      );
    }
    return text;
  }
}

TextAlign _alignOf(String align) {
  switch (align) {
    case 'center':
      return TextAlign.center;
    case 'right':
      return TextAlign.right;
    case 'justify':
      return TextAlign.justify;
    default:
      return TextAlign.left;
  }
}

Color? _parseColor(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  var hex = s.startsWith('#') ? s.substring(1) : s;
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length == 8) {
    final v = int.tryParse(hex, radix: 16);
    if (v != null) return Color(v);
  }
  return null;
}

const Color _defaultInk = Color(0xFF1F2937);

// ---------------------------------------------------------------------------
// Document model + styled runs + HTML serialisation.
// ---------------------------------------------------------------------------

enum _Block { para, bullet, number }

class _Span {
  int start, end;
  String kind; // b,i,u,s,color,mark,size
  String? value;
  _Span(this.start, this.end, this.kind, [this.value]);
  _Span copy() => _Span(start, end, kind, value);
}

class _Line {
  String text;
  _Block block;
  String align; // left|center|right|justify
  List<_Span> spans;
  int number; // display number for ordered lists
  _Line(
      {required this.text,
      this.block = _Block.para,
      this.align = 'left',
      List<_Span>? spans,
      this.number = 0})
      : spans = spans ?? [];
  _Line copy() => _Line(
      text: text,
      block: block,
      align: align,
      spans: spans.map((s) => s.copy()).toList(),
      number: number);
}

/// One uniformly-styled run inside a line.
class _Run {
  int start, end;
  bool bold, italic, underline, strike;
  Color color;
  Color? bg;
  double fontSize;
  _Run(
      {required this.start,
      required this.end,
      this.bold = false,
      this.italic = false,
      this.underline = false,
      this.strike = false,
      this.color = _defaultInk,
      this.bg,
      required this.fontSize});
}

double _sizeForValue(String? value, double base) {
  switch ((value ?? 'normal').toLowerCase()) {
    case 'small':
      return base - 2.5;
    case 'large':
      return base + 2.5;
    case 'h1':
      return base + 8.5;
    case 'h2':
      return base + 5.5;
    case 'h3':
      return base + 3;
    default:
      return base;
  }
}

bool _sizeIsHeading(String? value) {
  final v = (value ?? '').toLowerCase();
  return v == 'h1' || v == 'h2' || v == 'h3';
}

/// Splits a line into uniformly-styled runs. Shared by the live
/// editor and the read-only renderer so both look identical.
List<_Run> _computeRuns(_Line line, double base) {
  if (line.text.isEmpty) return [];
  final cuts = <int>{0, line.text.length};
  for (final s in line.spans) {
    cuts.add(s.start.clamp(0, line.text.length));
    cuts.add(s.end.clamp(0, line.text.length));
  }
  final points = cuts.toList()..sort();
  final out = <_Run>[];
  for (int i = 0; i < points.length - 1; i++) {
    final a = points[i], b = points[i + 1];
    if (a >= b) continue;
    var bold = false, italic = false, underline = false, strike = false;
    var color = _defaultInk;
    Color? bg;
    var size = base;
    for (final s in line.spans) {
      if (s.start <= a && s.end >= b) {
        switch (s.kind) {
          case 'b':
            bold = true;
            break;
          case 'i':
            italic = true;
            break;
          case 'u':
            underline = true;
            break;
          case 's':
            strike = true;
            break;
          case 'color':
            color = _parseColor(s.value) ?? _defaultInk;
            break;
          case 'mark':
            bg = _parseColor(s.value) ?? const Color(0xFFFFFF00);
            break;
          case 'size':
            size = _sizeForValue(s.value, base);
            if (_sizeIsHeading(s.value)) bold = true;
            break;
        }
      }
    }
    out.add(_Run(
        start: a,
        end: b,
        bold: bold,
        italic: italic,
        underline: underline,
        strike: strike,
        color: color,
        bg: bg,
        fontSize: size));
  }
  return out;
}

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&');

String _inlineHtml(String text, List<_Span> spans) {
  if (text.isEmpty) return '';
  final opens = <int, List<String>>{};
  final closes = <int, List<String>>{};
  for (final s in spans) {
    final a = s.start.clamp(0, text.length);
    final b = s.end.clamp(0, text.length);
    if (a >= b) continue;
    String open, close;
    switch (s.kind) {
      case 'b':
        open = '<b>';
        close = '</b>';
        break;
      case 'i':
        open = '<i>';
        close = '</i>';
        break;
      case 'u':
        open = '<u>';
        close = '</u>';
        break;
      case 's':
        open = '<s>';
        close = '</s>';
        break;
      case 'mark':
        open = '<mark${s.value != null ? ' color="${s.value}"' : ''}>';
        close = '</mark>';
        break;
      case 'color':
        open = '<font color="${s.value ?? '#1F2937'}">';
        close = '</font>';
        break;
      case 'size':
        open = '<size v="${s.value ?? 'normal'}">';
        close = '</size>';
        break;
      default:
        continue;
    }
    (opens[a] ??= []).add(open);
    (closes[b] ??= []).insert(0, close);
  }
  final buf = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    if (opens.containsKey(i)) buf.write(opens[i]!.join());
    buf.write(_escape(text[i]));
    if (closes.containsKey(i + 1)) buf.write(closes[i + 1]!.join());
  }
  return buf.toString();
}

String _buildNoticeHtml(List<_Line> lines) {
  final buf = StringBuffer();
  int i = 0;
  void flushList(_Block kind, List<_Line> group) {
    buf.write(kind == _Block.bullet ? '<ul>' : '<ol>');
    for (final l in group) {
      buf.write('<li');
      if (l.align != 'left') buf.write(' align="${l.align}"');
      buf.write('>');
      buf.write(_inlineHtml(l.text, l.spans));
      buf.write('</li>');
    }
    buf.write(kind == _Block.bullet ? '</ul>' : '</ol>');
  }

  while (i < lines.length) {
    final l = lines[i];
    if (l.block == _Block.bullet || l.block == _Block.number) {
      final kind = l.block;
      final group = <_Line>[];
      while (i < lines.length && lines[i].block == kind) {
        group.add(lines[i]);
        i++;
      }
      flushList(kind, group);
      continue;
    }
    var extra = '';
    if (l.align != 'left') extra += ' align="${l.align}"';
    buf.write('<p$extra>${_inlineHtml(l.text, l.spans)}</p>');
    i++;
  }
  return buf.toString();
}

String _alignAttr(String attrs) {
  final m = RegExp(r'''align\s*=\s*["']?(\w+)''', caseSensitive: false)
      .firstMatch(attrs);
  final a = (m?.group(1) ?? 'left').toLowerCase();
  return ['left', 'center', 'right', 'justify'].contains(a) ? a : 'left';
}

void _addInlineLines(
    List<_Line> lines, String inner, _Block block, String align) {
  final tagRe = RegExp(r'<(/?)(b|i|u|s|mark|font|size|br)([^>]*)>',
      caseSensitive: false);
  final textBuf = StringBuffer();
  final stack = <Map<String, String?>>[];
  final allSpans = <_Span>[];
  void pushText(String chunk) => textBuf.write(_unescape(chunk));

  int pos = 0;
  for (final m in tagRe.allMatches(inner)) {
    pushText(inner.substring(pos, m.start));
    final closing = m.group(1) == '/';
    final tag = m.group(2)!.toLowerCase();
    final attrs = m.group(3) ?? '';
    if (tag == 'br' && !closing) {
      textBuf.write('\n');
    } else if (!closing) {
      String? value;
      if (tag == 'font' || tag == 'mark') {
        value = RegExp(r'''color\s*=\s*["']?([^"'\s>]+)''',
                caseSensitive: false)
            .firstMatch(attrs)
            ?.group(1);
      } else if (tag == 'size') {
        value = RegExp(r'''v\s*=\s*["']?([^"'\s>]+)''',
                caseSensitive: false)
            .firstMatch(attrs)
            ?.group(1);
      }
      stack.add(
          {'kind': tag, 'value': value, 'at': textBuf.length.toString()});
    } else {
      for (int k = stack.length - 1; k >= 0; k--) {
        if (stack[k]['kind'] == tag) {
          final at = int.parse(stack[k]['at']!);
          if (textBuf.length > at &&
              ['b', 'i', 'u', 's', 'mark', 'font', 'size']
                  .contains(tag)) {
            allSpans.add(_Span(at, textBuf.length,
                tag == 'font' ? 'color' : tag, stack[k]['value']));
          }
          stack.removeAt(k);
          break;
        }
      }
    }
    pos = m.end;
  }
  pushText(inner.substring(pos));
  final parts = textBuf.toString().split('\n');
  int offset = 0;
  for (final part in parts) {
    final mine = <_Span>[];
    for (final s in allSpans) {
      final a = (s.start - offset).clamp(0, part.length);
      final b = (s.end - offset).clamp(0, part.length);
      if (a < b) mine.add(_Span(a, b, s.kind, s.value));
    }
    lines.add(_Line(text: part, block: block, align: align, spans: mine));
    offset += part.length + 1;
  }
}

/// Parses our HTML subset (plus legacy headings and plain text) back
/// into lines, so Edit preserves every formatting choice.
List<_Line> _parseNoticeHtml(String html) {
  final src = (html).trim();
  if (src.isEmpty) return [_Line(text: '')];
  final lines = <_Line>[];
  final blockRe = RegExp(
      r'<(p|h1|h2|h3|ul|ol)([^>]*)>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true);
  final matches = blockRe.allMatches(src).toList();
  if (matches.isEmpty) {
    for (final part in _unescape(src).split('\n')) {
      lines.add(_Line(text: part));
    }
    return lines;
  }

  for (final m in matches) {
    final tag = m.group(1)!.toLowerCase();
    final attrs = m.group(2) ?? '';
    final inner = m.group(3) ?? '';
    final align = _alignAttr(attrs);
    if (tag == 'ul' || tag == 'ol') {
      final liRe = RegExp(r'<li([^>]*)>(.*?)</li>',
          caseSensitive: false, dotAll: true);
      final items = liRe.allMatches(inner).toList();
      if (items.isEmpty) {
        _addInlineLines(lines, inner,
            tag == 'ul' ? _Block.bullet : _Block.number, align);
      } else {
        for (final li in items) {
          _addInlineLines(lines, li.group(2) ?? '',
              tag == 'ul' ? _Block.bullet : _Block.number,
              _alignAttr(li.group(1) ?? ''));
        }
      }
    } else if (tag == 'h1' || tag == 'h2' || tag == 'h3') {
      // Legacy headings become big bold inline runs.
      final before = lines.length;
      _addInlineLines(lines, inner, _Block.para, align);
      for (int k = before; k < lines.length; k++) {
        final l = lines[k];
        if (l.text.isNotEmpty) {
          l.spans.add(_Span(0, l.text.length, 'size', tag));
          l.spans.add(_Span(0, l.text.length, 'b'));
        }
      }
    } else {
      final size = RegExp(r'''size\s*=\s*["']?(\w+)''',
              caseSensitive: false)
          .firstMatch(attrs)
          ?.group(1)
          ?.toLowerCase();
      final before = lines.length;
      _addInlineLines(lines, inner, _Block.para, align);
      if (size == 'small' || size == 'large') {
        for (int k = before; k < lines.length; k++) {
          final l = lines[k];
          if (l.text.isNotEmpty) {
            l.spans.add(_Span(0, l.text.length, 'size', size));
          }
        }
      }
    }
  }
  int n = 0;
  _Block? prev;
  for (final l in lines) {
    if (l.block == _Block.number) {
      n = (prev == _Block.number) ? n + 1 : 1;
      l.number = n;
    } else {
      n = 0;
    }
    prev = l.block;
  }
  return lines;
}

// ---------------------------------------------------------------------------
// Composer — Word-style toolbar + live WYSIWYG editing field.
// ---------------------------------------------------------------------------

/// Controller that paints the document's formatting live inside the
/// typing area (bold, colors, sizes, bullets…), like a Word editor.
class _ComposerController extends TextEditingController {
  final List<_Line> Function() getLines;
  final double baseSize;
  _ComposerController({required this.getLines, this.baseSize = 14});

  String _prefixFor(_Line l) {
    if (l.block == _Block.bullet) return '• ';
    if (l.block == _Block.number) return '${l.number}. ';
    return '';
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final lines = getLines();
    final fieldLines = value.text.split('\n');
    final defStyle = GoogleFonts.poppins(
        fontSize: baseSize, color: _defaultInk, height: 1.6);
    if (lines.length != fieldLines.length) {
      return TextSpan(style: style ?? defStyle, text: value.text);
    }
    final children = <InlineSpan>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final prefix = _prefixFor(line);
      if (prefix.isNotEmpty) {
        children.add(TextSpan(text: prefix, style: defStyle));
      }
      final runs = _computeRuns(line, baseSize);
      if (runs.isEmpty) {
        children.add(TextSpan(text: line.text, style: defStyle));
      } else {
        for (final r in runs) {
          children.add(TextSpan(
            text: line.text.substring(r.start, r.end),
            style: GoogleFonts.poppins(
              fontSize: r.fontSize,
              fontWeight: r.bold ? FontWeight.bold : FontWeight.normal,
              fontStyle:
                  r.italic ? FontStyle.italic : FontStyle.normal,
              color: r.color,
              backgroundColor: r.bg,
              height: 1.6,
              decoration: r.underline && r.strike
                  ? TextDecoration.combine([
                      TextDecoration.underline,
                      TextDecoration.lineThrough
                    ])
                  : r.underline
                      ? TextDecoration.underline
                      : r.strike
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
            ),
          ));
        }
      }
      if (i < lines.length - 1) {
        children.add(TextSpan(text: '\n', style: defStyle));
      }
    }
    return TextSpan(style: style, children: children);
  }
}

class NoticeComposer extends StatefulWidget {
  final String initialHtml;
  final ValueChanged<String> onChanged;
  const NoticeComposer(
      {super.key, required this.initialHtml, required this.onChanged});

  @override
  State<NoticeComposer> createState() => _NoticeComposerState();
}

class _NoticeComposerState extends State<NoticeComposer> {
  late List<_Line> _lines;
  late _ComposerController _controller;
  final _focus = FocusNode();
  bool _preview = false;
  bool _syncing = false;
  String _lastFieldText = '';

  final List<String> _undo = [];
  final List<String> _redo = [];
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  static const _textColors = [
    '#1F2937', '#B91C1C', '#1D4ED8', '#15803D', '#B45309', '#7B1FA2',
    '#0E7490', '#BE185D',
  ];
  static const _markColors = ['#FEF08A', '#BBF7D0', '#FBCFE8', '#BFDBFE'];

  static const _sizeOptions = [
    ('small', 'Small'),
    ('normal', 'Normal'),
    ('large', 'Large'),
    ('h1', 'Heading 1'),
    ('h2', 'Heading 2'),
    ('h3', 'Heading 3'),
  ];

  @override
  void initState() {
    super.initState();
    _lines = _parseNoticeHtml(widget.initialHtml);
    _renumber();
    _controller =
        _ComposerController(getLines: () => _lines, baseSize: 14);
    _controller.text = _fieldText();
    _lastFieldText = _controller.text;
    _controller.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onFieldChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // -- field text with virtual list prefixes -----------------------------------
  String _prefixFor(int index) {
    final l = _lines[index];
    if (l.block == _Block.bullet) return '• ';
    if (l.block == _Block.number) return '${l.number}. ';
    return '';
  }

  String _fieldText() {
    final buf = StringBuffer();
    for (int i = 0; i < _lines.length; i++) {
      if (i > 0) buf.write('\n');
      buf.write(_prefixFor(i));
      buf.write(_lines[i].text);
    }
    return buf.toString();
  }

  List<int> _lineStarts(String field) {
    final starts = <int>[0];
    for (int i = 0; i < field.length; i++) {
      if (field.codeUnitAt(i) == 10) starts.add(i + 1);
    }
    return starts;
  }

  void _renumber() {
    int n = 0;
    _Block? prev;
    for (final l in _lines) {
      if (l.block == _Block.number) {
        n = (prev == _Block.number) ? n + 1 : 1;
        l.number = n;
      } else {
        n = 0;
        l.number = 0;
      }
      prev = l.block;
    }
  }

  String _snapshot() => _buildNoticeHtml(_lines);

  void _pushUndo() {
    _undo.add(_snapshot());
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    _lastPush = DateTime.now();
  }

  void _restore(String html) {
    _lines = _parseNoticeHtml(html);
    _renumber();
    _syncing = true;
    _controller.text = _fieldText();
    _lastFieldText = _controller.text;
    _syncing = false;
    widget.onChanged(_buildNoticeHtml(_lines));
    setState(() {});
  }

  void _undoOp() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void _redoOp() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  void _emit() => widget.onChanged(_buildNoticeHtml(_lines));

  // -- sync typed edits back into the model --------------------------------------
  void _onFieldChanged() {
    if (_syncing) return;
    final field = _controller.text;
    if (field != _lastFieldText) {
      final rawLines = field.split('\n');
      final newLines = <_Line>[];
      final pairCount =
          rawLines.length < _lines.length ? rawLines.length : _lines.length;
      for (int i = 0; i < pairCount; i++) {
        var raw = rawLines[i];
        final old = _lines[i];
        final prefix = _prefixFor(i);
        if (prefix.isNotEmpty && raw.startsWith(prefix)) {
          raw = raw.substring(prefix.length);
        } else if (old.block == _Block.number) {
          final m = RegExp(r'^\d+\.\s').firstMatch(raw);
          if (m != null) raw = raw.substring(m.end);
        }
        newLines.add(_shiftLine(old, raw));
      }
      for (int i = pairCount; i < rawLines.length; i++) {
        newLines.add(_Line(text: rawLines[i]));
      }
      _lines = newLines;
      if (_lines.isEmpty) _lines = [_Line(text: '')];
      _renumber();
      _lastFieldText = _controller.text;
      if (DateTime.now().difference(_lastPush).inSeconds > 2) {
        _undo.add(_snapshot());
        if (_undo.length > 60) _undo.removeAt(0);
        _redo.clear();
        _lastPush = DateTime.now();
      }
      _emit();
    }
    // Refresh toolbar active states (also fires on selection moves).
    if (mounted) setState(() {});
  }

  _Line _shiftLine(_Line old, String raw) {
    final a = old.text;
    int pre = 0;
    while (pre < a.length && pre < raw.length && a[pre] == raw[pre]) {
      pre++;
    }
    int suf = 0;
    while (suf < a.length - pre &&
        suf < raw.length - pre &&
        a[a.length - 1 - suf] == raw[raw.length - 1 - suf]) {
      suf++;
    }
    final removed = (a.length - pre - suf);
    final inserted = raw.substring(pre, raw.length - suf);
    final out = <_Span>[];
    for (final s in old.spans) {
      int ns = s.start, ne = s.end;
      if (s.end <= pre) {
        // unchanged
      } else if (s.start >= pre + removed) {
        final d = inserted.length - removed;
        ns += d;
        ne += d;
      } else {
        if (s.start < pre) {
          ne = pre +
              inserted.length +
              (s.end - (pre + removed)).clamp(0, 1 << 30);
        } else if (s.end > pre + removed) {
          ns = pre + inserted.length;
          ne = ns + (s.end - (pre + removed));
        } else {
          continue;
        }
      }
      ns = ns.clamp(0, raw.length);
      ne = ne.clamp(0, raw.length);
      if (ns < ne) out.add(_Span(ns, ne, s.kind, s.value));
    }
    return _Line(
        text: raw, block: old.block, align: old.align, spans: out);
  }

  // -- selection helpers -----------------------------------------------------------
  TextSelection get _sel => _controller.selection;

  List<int> _selectedLines() {
    final field = _controller.text;
    final starts = _lineStarts(field);
    int s = _sel.start < 0 ? field.length : _sel.start;
    int e = _sel.end < 0 ? field.length : _sel.end;
    if (s > e) {
      final t = s;
      s = e;
      e = t;
    }
    final out = <int>[];
    for (int i = 0; i < _lines.length; i++) {
      final ls = i < starts.length ? starts[i] : field.length;
      final le = i + 1 < starts.length ? starts[i + 1] - 1 : field.length;
      if (e < ls || s > le) continue;
      out.add(i);
    }
    if (out.isEmpty && _lines.isNotEmpty) out.add(_lines.length - 1);
    return out;
  }

  (int, int)? _rangeInLine(int i) {
    final field = _controller.text;
    final starts = _lineStarts(field);
    if (i >= starts.length || i >= _lines.length) return null;
    final ls = starts[i];
    final prefix = _prefixFor(i).length;
    int s = _sel.start < 0 ? field.length : _sel.start;
    int e = _sel.end < 0 ? field.length : _sel.end;
    if (s > e) {
      final t = s;
      s = e;
      e = t;
    }
    final textLen = _lines[i].text.length;
    int a = (s - ls - prefix).clamp(0, textLen);
    int b = (e - ls - prefix).clamp(0, textLen);
    if (a > b) {
      final t = a;
      a = b;
      b = t;
    }
    return (a, b);
  }

  bool get _hasRange {
    if (!_sel.isValid) return false;
    return _sel.start != _sel.end;
  }

  void _hint(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
      backgroundColor: const Color(0xFF0F172A),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _afterModelChange({bool keepSelection = true}) {
    final sel = _controller.selection;
    _renumber();
    _syncing = true;
    _controller.text = _fieldText();
    _lastFieldText = _controller.text;
    if (keepSelection) {
      final len = _controller.text.length;
      _controller.selection = TextSelection(
        baseOffset: sel.start.clamp(0, len),
        extentOffset: sel.end.clamp(0, len),
      );
    }
    _syncing = false;
    _emit();
    setState(() {});
  }

  // -- toolbar actions ---------------------------------------------------------------
  void _toggleInline(String kind, [String? value]) {
    if (!_hasRange) {
      _hint('Select some text first, then apply formatting.');
      return;
    }
    _pushUndo();
    for (final i in _selectedLines()) {
      final r = _rangeInLine(i);
      if (r == null || r.$1 >= r.$2) continue;
      final line = _lines[i];
      final covered = line.spans.any((s) =>
          s.kind == kind &&
          (value == null || s.value == value) &&
          s.start <= r.$1 &&
          s.end >= r.$2);
      line.spans.removeWhere((s) =>
          s.kind == kind &&
          (value == null || s.value == value) &&
          s.start < r.$2 &&
          s.end > r.$1);
      if (!covered) line.spans.add(_Span(r.$1, r.$2, kind, value));
    }
    _afterModelChange();
  }

  /// Sizes replace each other (like Word) instead of stacking.
  void _applySize(String value) {
    if (!_hasRange) {
      _hint('Select some text first, then pick a size.');
      return;
    }
    _pushUndo();
    for (final i in _selectedLines()) {
      final r = _rangeInLine(i);
      if (r == null || r.$1 >= r.$2) continue;
      final line = _lines[i];
      line.spans.removeWhere(
          (s) => s.kind == 'size' && s.start < r.$2 && s.end > r.$1);
      if (value != 'normal') line.spans.add(_Span(r.$1, r.$2, 'size', value));
    }
    _afterModelChange();
  }

  String _selectionSize() {
    String? found;
    var any = false;
    for (final i in _selectedLines()) {
      final r = _rangeInLine(i);
      if (r == null || r.$1 >= r.$2) continue;
      for (int p = r.$1; p < r.$2; p++) {
        any = true;
        String v = 'normal';
        for (final s in _lines[i].spans) {
          if (s.kind == 'size' && s.start <= p && s.end > p) {
            v = (s.value ?? 'normal').toLowerCase();
            break;
          }
        }
        found ??= v;
        if (found != v) return 'normal';
      }
    }
    return any ? (found ?? 'normal') : 'normal';
  }

  void _setBlock(_Block block) {
    _pushUndo();
    for (final i in _selectedLines()) {
      _lines[i].block = block;
    }
    _afterModelChange();
  }

  void _setAlign(String align) {
    _pushUndo();
    for (final i in _selectedLines()) {
      _lines[i].align = align;
    }
    _afterModelChange();
  }

  void _clearFormatting() {
    _pushUndo();
    if (_hasRange) {
      for (final i in _selectedLines()) {
        final r = _rangeInLine(i);
        final line = _lines[i];
        if (r == null || r.$1 >= r.$2) {
          line.spans.clear();
          line.block = _Block.para;
          line.align = 'left';
        } else {
          line.spans
              .removeWhere((s) => s.start < r.$2 && s.end > r.$1);
        }
      }
    } else {
      for (final i in _selectedLines()) {
        _lines[i].spans.clear();
        _lines[i].block = _Block.para;
        _lines[i].align = 'left';
      }
    }
    _afterModelChange();
  }

  bool _inlineActive(String kind, [String? value]) {
    bool cursorAt(int at, _Line line) => line.spans.any((s) =>
        s.kind == kind &&
        (value == null || s.value == value) &&
        s.start < at &&
        s.end >= at);
    if (!_hasRange) {
      final lines = _selectedLines();
      if (lines.isEmpty) return false;
      final r = _rangeInLine(lines.first);
      if (r == null) return false;
      var at = r.$1 - 1;
      if (at < 0) at = 0;
      return cursorAt(at, _lines[lines.first]);
    }
    for (final i in _selectedLines()) {
      final r = _rangeInLine(i);
      if (r == null || r.$1 >= r.$2) continue;
      final ok = _lines[i].spans.any((s) =>
          s.kind == kind &&
          (value == null || s.value == value) &&
          s.start <= r.$1 &&
          s.end >= r.$2);
      if (!ok) return false;
    }
    return true;
  }

  bool _blockActive(_Block block) {
    final lines = _selectedLines();
    if (lines.isEmpty) return false;
    return lines.every((i) => _lines[i].block == block);
  }

  bool _alignActive(String align) {
    final lines = _selectedLines();
    if (lines.isEmpty) return false;
    return lines.every((i) => _lines[i].align == align);
  }

  void _pickColor({required bool highlight}) {
    final colors = highlight ? _markColors : _textColors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(highlight ? 'Highlight color' : 'Text color',
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in colors)
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleInline(
                      highlight ? 'mark' : 'color', c.toUpperCase());
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _parseColor(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _removeKind(highlight ? 'mark' : 'color');
              },
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Icon(Icons.block_rounded,
                    size: 20, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _removeKind(String kind) {
    if (!_hasRange) {
      _hint('Select some text first.');
      return;
    }
    _pushUndo();
    for (final i in _selectedLines()) {
      final r = _rangeInLine(i);
      if (r == null || r.$1 >= r.$2) continue;
      _lines[i]
          .spans
          .removeWhere((s) => s.kind == kind && s.start < r.$2 && s.end > r.$1);
    }
    _afterModelChange();
  }

  // -- build -----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          const Divider(height: 1),
          if (_preview)
            Container(
              constraints: const BoxConstraints(minHeight: 140),
              padding: const EdgeInsets.all(14),
              child: NoticeContentView(_buildNoticeHtml(_lines)),
            )
          else
            TextField(
              controller: _controller,
              focusNode: _focus,
              maxLines: 8,
              minLines: 5,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: const Color(0xFF111827), height: 1.6),
              decoration: InputDecoration(
                hintText: 'Write your notice here...',
                hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400, fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Wrap(
        spacing: 2,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _toolBtn(Icons.format_bold_rounded, 'Bold', _inlineActive('b'),
              () => _toggleInline('b'),
              label: 'B', boldLabel: true),
          _toolBtn(Icons.format_italic_rounded, 'Italic', _inlineActive('i'),
              () => _toggleInline('i'),
              label: 'I', italicLabel: true),
          _toolBtn(Icons.format_underline_rounded, 'Underline',
              _inlineActive('u'), () => _toggleInline('u'),
              label: 'U', underlineLabel: true),
          _toolBtn(Icons.strikethrough_s_rounded, 'Strikethrough',
              _inlineActive('s'), () => _toggleInline('s')),
          _divider(),
          _sizeDropdown(),
          _colorBtn(),
          _markBtn(),
          _divider(),
          _toolBtn(Icons.format_align_left_rounded, 'Align left',
              _alignActive('left'), () => _setAlign('left')),
          _toolBtn(Icons.format_align_center_rounded, 'Center',
              _alignActive('center'), () => _setAlign('center')),
          _toolBtn(Icons.format_align_right_rounded, 'Align right',
              _alignActive('right'), () => _setAlign('right')),
          _toolBtn(Icons.format_align_justify_rounded, 'Justify',
              _alignActive('justify'), () => _setAlign('justify')),
          _divider(),
          _toolBtn(Icons.format_list_bulleted_rounded, 'Bullet list',
              _blockActive(_Block.bullet),
              () => _setBlock(_blockActive(_Block.bullet)
                  ? _Block.para
                  : _Block.bullet)),
          _toolBtn(Icons.format_list_numbered_rounded, 'Numbered list',
              _blockActive(_Block.number),
              () => _setBlock(_blockActive(_Block.number)
                  ? _Block.para
                  : _Block.number)),
          _divider(),
          _toolBtn(Icons.undo_rounded, 'Undo', false, _undoOp,
              disabled: _undo.isEmpty),
          _toolBtn(Icons.redo_rounded, 'Redo', false, _redoOp,
              disabled: _redo.isEmpty),
          _toolBtn(Icons.format_clear_rounded, 'Clear formatting', false,
              _clearFormatting),
          _divider(),
          _toolBtn(
              _preview ? Icons.edit_rounded : Icons.visibility_outlined,
              _preview ? 'Edit' : 'Preview',
              _preview,
              () => setState(() => _preview = !_preview)),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
        width: 1,
        height: 26,
        color: Colors.grey.shade300,
        margin: const EdgeInsets.symmetric(horizontal: 4));
  }

  Widget _toolBtn(IconData icon, String tip, bool active, VoidCallback onTap,
      {bool disabled = false,
      String? label,
      bool boldLabel = false,
      bool italicLabel = false,
      bool underlineLabel = false}) {
    final color = disabled
        ? Colors.grey.shade300
        : active
            ? Colors.white
            : const Color(0xFF334155);
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF1565C0) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: label != null
              ? Text(label,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight:
                        boldLabel ? FontWeight.w800 : FontWeight.w600,
                    fontStyle:
                        italicLabel ? FontStyle.italic : FontStyle.normal,
                    decoration: underlineLabel
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    color: color,
                  ))
              : Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }

  Widget _sizeDropdown() {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectionSize(),
          style: GoogleFonts.poppins(
              fontSize: 12.5, color: const Color(0xFF334155)),
          items: [
            for (final (v, l) in _sizeOptions)
              DropdownMenuItem(value: v, child: Text(l)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _applySize(v);
          },
        ),
      ),
    );
  }

  Widget _colorBtn() {
    return Tooltip(
      message: 'Text color',
      child: InkWell(
        onTap: () => _pickColor(highlight: false),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('A',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF334155),
                      height: 1)),
              Container(height: 4, width: 18, color: Colors.red.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _markBtn() {
    return Tooltip(
      message: 'Highlight',
      child: InkWell(
        onTap: () => _pickColor(highlight: true),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: const Icon(Icons.highlight_rounded,
              size: 19, color: Color(0xFF334155)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reader modal shared by Admin / Teacher / Student.
// ---------------------------------------------------------------------------

void showNoticeDialog(
  BuildContext context, {
  required String title,
  required String html,
  required String dateTimeLabel,
  String? audienceLabel,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign_rounded,
                    color: Color(0xFF1565C0), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('📢 $title',
                    style: GoogleFonts.poppins(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827))),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(dateTimeLabel,
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1565C0))),
              ),
              if (audienceLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B1FA2).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(audienceLabel,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF7B1FA2))),
                ),
            ]),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: NoticeContentView(html),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text('Close',
                    style:
                        GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// True when the composer HTML holds no real text.
bool noticeHtmlIsEmpty(String html) =>
    NoticeService.plainTextOf(html).trim().isEmpty;
