abstract final class AppRoutes {
  static const onboarding = '/onboarding';

  /// The walkthrough. Outside the shell: it is a screen of its own, not a
  /// tab. `?replay=1` returns to where it was opened from instead of going
  /// on to the home tab.
  static const tutorial = '/tutorial';

  /// Address search, full screen. Pushed from onboarding and from the home
  /// tab's district switch; pops with the chosen `AddressSuggestion`.
  /// Reachable without a district -- onboarding is where one is chosen.
  static const addressSearch = '/address-search';

  /// Writing a resident review, full screen over the tabs. Pops with `true`
  /// once a review is posted.
  static const reviewCompose = '/review-compose';
  static const home = '/';
  static const history = '/history';
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

  /// Direction analysis: policy positions, the incumbent's trend, local
  /// issues. A sibling of the match under the same tab and the same
  /// disclosure, reached from the switch at the top of the AI tab.
  static const aiDirectionSegment = 'direction';

  static const aiDirection = '$aiMatch/direction';
}
