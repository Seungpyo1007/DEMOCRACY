abstract final class AppRoutes {
  static const onboarding = '/onboarding';
  static const home = '/';
  static const tracker = '/tracker';
  static const aiMatch = '/ai-match';
  static const community = '/community';
  static const results = '/results';

  /// A pledge's own page, and the app's first pushed route.
  ///
  /// Nested under the tracker so opening one keeps the tab bar and the branch
  /// it was opened from -- and so back returns to the list rather than to
  /// whichever tab was last selected.
  static const pledgeDetailSegment = 'pledges/:id';

  static String pledgeDetail(String id) => '$tracker/pledges/$id';
}
