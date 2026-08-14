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

  /// The weights and inputs a match ran on.
  ///
  /// Nested under the match screen so the disclosure's link keeps the reader
  /// in the tab they were reading, and back returns to the score they were
  /// questioning.
  static const algorithmLogSegment = 'log';

  static const algorithmLog = '$aiMatch/log';
}
