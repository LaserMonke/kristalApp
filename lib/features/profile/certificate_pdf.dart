import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the printable certificate.
///
/// A separate, plain-Dart-ish builder rather than a screenshot of the widget:
/// print output should be vector text at the printer's resolution, not a
/// bitmap of a phone screen.
///
/// The disclaimer is printed ON the certificate, not merely shown next to it
/// in the app. A gold-sealed page that leaves the building with no caveat is
/// exactly the artifact that gets mistaken for a professional credential, and
/// CLAUDE.md rules 1 and 3 do not stop applying once something is on paper.
/// What the certificate says about itself, shared by the screen and the
/// printed page so the two can never drift apart.
///
/// This is the sentence that keeps a gold-sealed page honest, so it lives in
/// one place and is asserted by a test.
const String certificateDisclaimer =
    'This certificate records completed study within the Stock Options '
    'Academy educational app. It is NOT a professional qualification, '
    'licence, or accreditation; it says nothing about trading ability; and '
    'it is not financial advice or a recommendation to buy or sell any '
    'security.';

Future<List<int>> buildCertificatePdf({
  required String learnerName,
  required String awardedOn,
  required String certificateId,
  required List<String> topics,
}) async {
  // The PDF built-ins are ASCII-only, and a learner's name is free text: with
  // Helvetica, "Jose" prints fine and "José" does not. A certificate that
  // misspells the name on it is worse than no certificate, so a Unicode font
  // is embedded (Roboto, Apache-2.0 — see assets/fonts/Roboto_LICENSE.txt).
  final pw.ThemeData theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
  );

  final pw.Document doc = pw.Document(
    title: 'Stock Options Academy - Certificate of Completion',
    author: 'Stock Options Academy',
    theme: theme,
  );

  const PdfColor gold = PdfColor.fromInt(0xFFC9A227);
  const PdfColor goldDeep = PdfColor.fromInt(0xFF8A6A1F);
  const PdfColor ink = PdfColor.fromInt(0xFF1A1A1A);
  const PdfColor muted = PdfColor.fromInt(0xFF5A5A5A);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      build: (pw.Context context) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: gold, width: 3),
        ),
        padding: const pw.EdgeInsets.all(6),
        child: pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: goldDeep, width: 0.8),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 46, vertical: 30),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Column(
                children: <pw.Widget>[
                  pw.Text(
                    'STOCK OPTIONS ACADEMY',
                    style: pw.TextStyle(
                      fontSize: 11,
                      letterSpacing: 3,
                      color: muted,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 14),
                  pw.Text(
                    'Certificate of Completion',
                    style: pw.TextStyle(
                      fontSize: 30,
                      color: ink,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Container(width: 130, height: 1.4, color: gold),
                ],
              ),
              pw.Column(
                children: <pw.Widget>[
                  pw.Text(
                    'This is to certify that',
                    style: const pw.TextStyle(fontSize: 11, color: muted),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    learnerName,
                    style: pw.TextStyle(
                      fontSize: 26,
                      color: ink,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.SizedBox(
                    width: 470,
                    child: pw.Text(
                      'has completed every lesson and its assessment in the '
                      'Stock Options Academy curriculum, covering '
                      '${_sentenceList(topics)}.',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(
                        fontSize: 11,
                        color: ink,
                        lineSpacing: 3,
                      ),
                    ),
                  ),
                ],
              ),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: <pw.Widget>[
                  _signatureBlock('Awarded', awardedOn, gold, muted, ink),
                  _seal(gold, goldDeep),
                  _signatureBlock(
                    'Certificate ID',
                    certificateId,
                    gold,
                    muted,
                    ink,
                  ),
                ],
              ),
              pw.SizedBox(
                width: 640,
                child: pw.Text(
                  certificateDisclaimer,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: muted,
                    lineSpacing: 1.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  return doc.save();
}

pw.Widget _signatureBlock(
  String label,
  String value,
  PdfColor gold,
  PdfColor muted,
  PdfColor ink,
) => pw.SizedBox(
  width: 170,
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: <pw.Widget>[
      pw.Text(value, style: pw.TextStyle(fontSize: 11, color: ink)),
      pw.SizedBox(height: 4),
      pw.Container(height: 0.8, color: gold),
      pw.SizedBox(height: 4),
      pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(fontSize: 7.5, letterSpacing: 1.4, color: muted),
      ),
    ],
  ),
);

/// The same struck-medal seal as the screen, drawn into the page.
pw.Widget _seal(PdfColor gold, PdfColor goldDeep) => pw.SizedBox(
  width: 92,
  height: 92,
  child: pw.CustomPaint(
    size: const PdfPoint(92, 92),
    painter: (PdfGraphics canvas, PdfPoint size) {
      const double r = 46;
      // Scalloped rim.
      canvas.setFillColor(gold);
      for (int i = 0; i < 48; i++) {
        final double a = i * math.pi / 24 - math.pi / 2;
        final double radius = i.isEven ? r : r * 0.88;
        final double x = r + math.cos(a) * radius;
        final double y = r + math.sin(a) * radius;
        i == 0 ? canvas.moveTo(x, y) : canvas.lineTo(x, y);
      }
      canvas
        ..closePath()
        ..fillPath();

      // Face.
      canvas
        ..setFillColor(goldDeep)
        ..drawEllipse(r, r, r * 0.78, r * 0.78)
        ..fillPath();

      // Star.
      canvas.setFillColor(gold);
      for (int i = 0; i < 10; i++) {
        final double a = i * math.pi / 5 - math.pi / 2;
        final double rr = i.isEven ? r * 0.42 : r * 0.18;
        final double x = r + math.cos(a) * rr;
        final double y = r + math.sin(a) * rr;
        i == 0 ? canvas.moveTo(x, y) : canvas.lineTo(x, y);
      }
      canvas
        ..closePath()
        ..fillPath();
    },
  ),
);

/// "a, b and c" — an Oxford-comma-free list for prose.
String _sentenceList(List<String> items) {
  if (items.isEmpty) return 'the full curriculum';
  if (items.length == 1) return items.single;
  return '${items.take(items.length - 1).join(', ')} and ${items.last}';
}
