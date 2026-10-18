import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_theme.dart';
import 'package:democracy/src/features/shared/presentation/source_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

final _gongbo = Uri.parse(
  'https://policy.nec.go.kr/policy_pdf/20240410/PDF/PBINFO_PUB/fixture.pdf',
);
final _page = Uri.parse('https://www.nesdc.go.kr/portal/bbs/B0000005/view.do');

final _source = SourceMetadata(
  sourceUrl: _gongbo,
  fetchedAt: DateTime.utc(2026, 9, 27, 3),
);

/// A stand-in for pdfrx's viewer, which needs PDFium and so cannot run
/// under `flutter test`.
Widget _fakeView(
  BuildContext context,
  PdfDocumentRef document,
  PdfViewerParams params,
) => const Center(child: Text('PDF 본문'));

Widget _app(Widget home) =>
    MaterialApp(theme: AppTheme.light(TargetPlatform.android), home: home);

void main() {
  group('isPdfSource', () {
    test('reads the path, whatever its case or query', () {
      expect(isPdfSource(_gongbo), isTrue);
      expect(isPdfSource(Uri.parse('https://a.go.kr/x/DOC.PDF?v=2')), isTrue);
      expect(isPdfSource(_page), isFalse);
      expect(isPdfSource(Uri.parse('https://a.go.kr/pdf/view')), isFalse);
    });
  });

  group('openSource', () {
    Future<List<Uri>> tapOpen(WidgetTester tester, Uri url) async {
      final browsed = <Uri>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => openSource(
                    context,
                    url,
                    source: _source,
                    title: '제22대 국회의원선거 선거공보',
                    browser: (url) async => browsed.add(url),
                    pdfView: _fakeView,
                  ),
                  child: const Text('열기'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      return browsed;
    }

    testWidgets('reads a PDF in the app, with its source in the header', (
      tester,
    ) async {
      final browsed = await tapOpen(tester, _gongbo);

      expect(browsed, isEmpty);
      expect(find.byType(SourceDocumentScreen), findsOneWidget);
      expect(find.text('PDF 본문'), findsOneWidget);
      expect(find.text('제22대 국회의원선거 선거공보'), findsOneWidget);
      expect(find.text('출처 policy.nec.go.kr · 9월 27일 기준'), findsOneWidget);
      expect(find.byTooltip('원문 사이트에서 열기'), findsOneWidget);
    });

    testWidgets('opens a web page in the in-app browser', (tester) async {
      final browsed = await tapOpen(tester, _page);

      expect(browsed, [_page]);
      expect(find.byType(SourceDocumentScreen), findsNothing);
    });
  });

  group('SourceDocumentScreen', () {
    testWidgets('shows the stamp and the progress while it loads', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SourceDocumentScreen(
            url: _gongbo,
            source: _source,
            pdfView: (context, document, params) =>
                params.loadingBannerBuilder!(context, 3 << 20, 18 << 20),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('원문 문서를 불러오는 중'), findsOneWidget);
      expect(find.text('3.0MB / 18.0MB'), findsOneWidget);
      expect(find.bySemanticsLabel('불러오는 중'), findsOneWidget);
    });

    testWidgets('on failure offers a retry and the publisher\'s own site', (
      tester,
    ) async {
      final documents = <PdfDocumentRef>[];
      final outside = <Uri>[];
      await tester.pumpWidget(
        _app(
          SourceDocumentScreen(
            url: _gongbo,
            source: _source,
            onOpenOutside: (url) async => outside.add(url),
            pdfView: (context, document, params) {
              documents.add(document);
              return params.errorBannerBuilder!(
                context,
                Exception('offline'),
                null,
                document,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SourceDocumentError), findsOneWidget);
      expect(find.text('원문 문서를 불러오지 못했습니다.'), findsOneWidget);
      // The attribution stays on screen when the document does not.
      expect(find.text('출처 policy.nec.go.kr · 9월 27일 기준'), findsOneWidget);

      await tester.tap(find.text('원문 사이트에서 열기 ↗'));
      await tester.pump();
      expect(outside, [_gongbo]);

      await tester.tap(find.byTooltip('원문 사이트에서 열기'));
      await tester.pump();
      expect(outside, [_gongbo, _gongbo]);

      final before = documents.length;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(documents.length, greaterThan(before));
      // A failed load is cached per key, so a retry has to use a new one.
      expect(documents.last.key, isNot(documents.first.key));
      expect(documents.last, isA<PdfDocumentRefUri>());
      expect((documents.last as PdfDocumentRefUri).uri, _gongbo);
    });

    testWidgets('without metadata, names the host it came from', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(SourceDocumentScreen(url: _gongbo, pdfView: _fakeView)),
      );
      await tester.pumpAndSettle();

      expect(find.text('원문 문서'), findsOneWidget);
      expect(find.text('출처 policy.nec.go.kr'), findsOneWidget);
    });
  });
}
