/// Raised when the data behind a screen does not exist yet for this district.
///
/// Different from a failure: nothing is broken and retrying will not help.
/// A seat can be vacant, a term's bills not yet loaded, a district's pledge
/// list not yet entered, so a real district can reach any of these before
/// the data does. A screen says "준비 중" for this, not
/// "불러오지 못했습니다", and never falls back to sample data -- a sample
/// candidate shown under a real district's name would be a fabricated fact.
class NotAvailableException implements Exception {
  const NotAvailableException(this.what);

  /// What is missing, for logs. Not shown to the user.
  final String what;

  @override
  String toString() => 'NotAvailableException: $what';
}
