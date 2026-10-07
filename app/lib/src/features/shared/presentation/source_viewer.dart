import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL somewhere and completes once it has been handed off.
typedef UrlOpener = Future<void> Function(Uri url);

/// Builds the viewer for one document. The default is pdfrx's [PdfViewer];
/// tests pass their own, since PDFium does not load under `flutter test`.
typedef PdfViewBuilder =
    Widget Function(
      BuildContext context,
      PdfDocumentRef document,
      PdfViewerParams params,
    );

/// Whether [url] names a PDF by its path.
///
/// Decided from the URL alone rather than a HEAD request's content type: the
/// tap should answer at once, and every PDF the app links to today (the NEC
/// 선거공보) ends in `.pdf`. A link that only turns out to be a PDF on the
/// wire still opens, in the in-app browser.
bool isPdfSource(Uri url) => url.path.toLowerCase().endsWith('.pdf');

/// Opens the original behind a figure without leaving the app.
///
/// A PDF gets [SourceDocumentScreen], a full page over the tabs. Anything
/// else opens in the platform's in-app browser (SFSafariViewController,
/// Chrome Custom Tabs), which keeps the reader one swipe from where they
/// were. Leaving for the system browser is left to the reader, from the
/// viewer's own 「원문 사이트에서 열기」.
///
/// [source] supplies the publisher and fetched time the viewer's header
/// shows. [browser] and [pdfView] are for tests.
Future<void> openSource(
  BuildContext context,
  Uri url, {
  SourceMetadata? source,
  String? title,
  UrlOpener? browser,
  PdfViewBuilder? pdfView,
}) async {
  if (isPdfSource(url)) {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => SourceDocumentScreen(
          url: url,
          source: source,
          title: title,
          pdfView: pdfView,
        ),
      ),
    );
    return;
  }
  await (browser ?? openInAppBrowser)(url);
}

/// The platform's in-app browser.
Future<void> openInAppBrowser(Uri url) async {
  await launchUrl(url, mode: LaunchMode.inAppBrowserView);
}

/// The system browser, for when the reader asks to leave.
Future<void> openOutsideApp(Uri url) async {
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

/// A source PDF, read in the app.
///
/// The header keeps the provenance the figure carried on its own page --
/// who published the document and when it was fetched -- so opening the
/// original never strips the attribution off it.
class SourceDocumentScreen extends StatefulWidget {
  const SourceDocumentScreen({
    required this.url,
    this.source,
    this.title,
    this.pdfView,
    this.onOpenOutside,
    super.key,
  });

  final Uri url;
  final SourceMetadata? source;

  /// What the document is, e.g. 「제22대 국회의원선거 선거공보」.
  final String? title;

  final PdfViewBuilder? pdfView;

  /// Defaults to [openOutsideApp]. Injected by tests.
  final UrlOpener? onOpenOutside;

  @override
  State<SourceDocumentScreen> createState() => _SourceDocumentScreenState();
}

class _SourceDocumentScreenState extends State<SourceDocumentScreen> {
  /// Bumped by 다시 시도. pdfrx shares one loaded document per key, a failed
  /// load included, so a retry has to ask under a key it has not seen.
  int _attempt = 0;
  late PdfDocumentRef _document = _reference();

  PdfDocumentRef _reference() => PdfDocumentRefUri(
    widget.url,
    // Range requests let the first pages draw before an 18MB 공보 is in.
    preferRangeAccess: true,
    timeout: const Duration(seconds: 30),
    key: PdfDocumentRefKey(widget.url.toString(), [_attempt]),
  );

  void _retry() => setState(() {
    _attempt++;
    _document = _reference();
  });

  Future<void> _openOutside() async {
    await (widget.onOpenOutside ?? openOutsideApp)(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final params = PdfViewerParams(
      backgroundColor: AppColors.neutral200,
      pageDropShadow: null,
      loadingBannerBuilder: (context, downloaded, total) =>
          _Loading(downloaded: downloaded, total: total),
      errorBannerBuilder: (context, error, stackTrace, document) =>
          SourceDocumentError(onRetry: _retry, onOpenOutside: _openOutside),
    );
    final view = widget.pdfView ?? _defaultView;

    return Scaffold(
      backgroundColor: AppColors.ground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: widget.title ?? '원문 문서',
            attribution: _attribution(),
            onOpenOutside: _openOutside,
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(_attempt),
              child: view(context, _document, params),
            ),
          ),
        ],
      ),
    );
  }

  String _attribution() {
    final source = widget.source;
    if (source == null) {
      return '출처 ${widget.url.host.replaceFirst('www.', '')}';
    }
    return '출처 ${source.publisher} · ${source.asOfLabel}';
  }

  static Widget _defaultView(
    BuildContext context,
    PdfDocumentRef document,
    PdfViewerParams params,
  ) {
    return PdfViewer(document, params: params);
  }
}

/// Back, what the document is and where it came from, and the way out to
/// the publisher's own site.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.attribution,
    required this.onOpenOutside,
  });

  final String title;
  final String attribution;
  final VoidCallback onOpenOutside;

  @override
  Widget build(BuildContext context) {
    final glass = Theme.of(context).extension<AppSurfaceTokens>()!.isGlass;

    final back = glass
        ? CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Icon(
              CupertinoIcons.chevron_back,
              size: 22,
              color: AppColors.ink,
              semanticLabel: '뒤로',
            ),
          )
        : IconButton(
            tooltip: '뒤로',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass ? AppColors.ground : AppColors.neutral100,
        border: const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x1,
            AppSpacing.x1,
            AppSpacing.x2,
            AppSpacing.x2,
          ),
          child: Row(
            children: [
              back,
              const SizedBox(width: AppSpacing.x1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.cardBody.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      attribution,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.disclaimer.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              AppToolbarButton(
                icon: AppIcons.source,
                label: '원문 사이트에서 열기',
                onPressed: onOpenOutside,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The stamp, and how much of the document is in when the size is known.
class _Loading extends StatelessWidget {
  const _Loading({required this.downloaded, required this.total});

  final int downloaded;
  final int? total;

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    final progress = total == null || total <= 0
        ? null
        : '${_mb(downloaded)}MB / ${_mb(total)}MB';

    return ColoredBox(
      color: AppColors.ground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const InkStampIndicator(size: 36),
            const SizedBox(height: AppSpacing.x3),
            Text(
              '원문 문서를 불러오는 중',
              style: AppTextStyles.cardBody.copyWith(
                color: AppColors.neutral700,
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.x1),
              Text(
                progress,
                style: AppTextStyles.disclaimer.copyWith(
                  color: AppColors.neutral600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A document that did not load: try again, or read it on the publisher's
/// site instead.
///
/// The way out is always offered. The original has to stay reachable even
/// when the in-app reader cannot draw it, or the source rule breaks on the
/// screen that exists to keep it.
class SourceDocumentError extends StatelessWidget {
  const SourceDocumentError({
    required this.onRetry,
    required this.onOpenOutside,
    super.key,
  });

  final VoidCallback onRetry;
  final VoidCallback onOpenOutside;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return ColoredBox(
      color: AppColors.ground,
      child: Center(
        child: Padding(
          padding: kPagePadding,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.neutral400),
              borderRadius: BorderRadius.circular(surface.cardRadius),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '원문 문서를 불러오지 못했습니다.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '연결 상태를 확인한 뒤 다시 시도하거나, 원문 사이트에서 직접 열어 볼 수 있습니다.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.neutral600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  Wrap(
                    spacing: AppSpacing.x2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('다시 시도'),
                      ),
                      TextButton(
                        onPressed: onOpenOutside,
                        child: const Text('원문 사이트에서 열기 ↗'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
