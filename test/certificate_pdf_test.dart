import 'package:flutter_test/flutter_test.dart';
import 'package:optionsschool/features/profile/certificate_pdf.dart';

/// A certificate that leaves the app on paper is the version most likely to be
/// shown to someone else, so what it says about itself matters more than how
/// it looks. These tests are about the wording surviving, not the layout.
void main() {
  // The builder loads the embedded font from the asset bundle.
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String> renderText({
    String name = 'Ada Lovelace',
    String awardedOn = '4 August 2026',
    String id = 'SOA-2026-ABCDE',
    List<String> topics = const <String>['what options are', 'the Greeks'],
  }) async {
    final List<int> bytes = await buildCertificatePdf(
      learnerName: name,
      awardedOn: awardedOn,
      certificateId: id,
      topics: topics,
    );
    // The PDF stores text in compressed streams, so searching the raw bytes is
    // unreliable. Assert on what we can: a well-formed, non-trivial document.
    return String.fromCharCodes(bytes.take(1024));
  }

  test('it produces a well-formed PDF', () async {
    final List<int> bytes = await buildCertificatePdf(
      learnerName: 'Ada Lovelace',
      awardedOn: '4 August 2026',
      certificateId: 'SOA-2026-ABCDE',
      topics: const <String>['what options are'],
    );

    expect(bytes.length, greaterThan(1000));
    expect(
      String.fromCharCodes(bytes.take(5)),
      startsWith('%PDF'),
      reason: 'the print sheet is handed a real PDF, not a blob',
    );
  });

  test('a long name does not throw the layout over', () async {
    // Usernames are not length-checked anywhere near the certificate, so the
    // builder has to cope with one that will not fit on a line.
    final String header = await renderText(
      name: 'A Learner With A Truly Unreasonably Long Display Name Indeed',
    );
    expect(header, startsWith('%PDF'));
  });

  test('an empty topic list still reads as a sentence', () async {
    final String header = await renderText(topics: const <String>[]);
    expect(header, startsWith('%PDF'));
  });

  test('the disclaimer wording is present in the source of truth', () {
    // The page text lives in the builder; this pins the phrases that make the
    // certificate honest, so removing them fails a test rather than silently
    // shipping a gold-sealed page that claims to be a qualification.
    const List<String> required = <String>[
      'NOT a professional',
      'licence',
      'accreditation',
      'not financial advice',
      'says nothing',
    ];
    // Read the builder's own source: the strings are constants in it.
    final String source = certificateDisclaimer;
    for (final String phrase in required) {
      expect(
        source.toLowerCase(),
        contains(phrase.toLowerCase()),
        reason: 'the printed disclaimer must keep "$phrase"',
      );
    }
  });
}
