import 'package:flutter/material.dart';

import '../../../core/models/audax_event.dart';
import 'audax_category.dart';

/// Whether an event is still taking entries. Derived on the client from the
/// event's dates — the API has no status field, so this is presentation only
/// and never round-trips anywhere.
enum AudaxRegistrationStatus {
  open,
  closed,

  /// The source calendar hasn't published a close date yet. Distinct from
  /// [closed]: entries may well open later.
  tba,
}

/// Status for [event] as of [now] (defaults to the current time).
///
/// A ride that has already happened reads [closed] whatever
/// `registrationCloseDate` says — the source calendar does ship past events
/// with a future or absent close date, and a green "Open" badge on a finished
/// brevet is worse than ignoring the field.
///
/// Comparisons are date-only: registration closing *today* is still open,
/// since the source publishes days rather than instants and a rider reading
/// "closes today" expects to be able to enter.
AudaxRegistrationStatus audaxRegistrationStatus(AudaxEvent event, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  if (_dateOnly(event.eventDate).isBefore(today)) return AudaxRegistrationStatus.closed;

  final close = event.registrationCloseDate;
  if (close == null) return AudaxRegistrationStatus.tba;
  return _dateOnly(close).isBefore(today)
      ? AudaxRegistrationStatus.closed
      : AudaxRegistrationStatus.open;
}

/// Midnight local on [d]'s calendar day. Dates arrive from
/// [AudaxEvent.fromJson] via `DateTime.parse`, which yields UTC for anything
/// with a `Z`/offset suffix — [DateTime.toLocal] first so the day is the one
/// the rider is actually living in.
DateTime _dateOnly(DateTime d) {
  final local = d.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Whether [date]'s calendar day is already behind us locally. Exposed so the
/// card can word "Registration closes/closed `<date>`" in the right tense —
/// which follows the date itself, not the badge: an event that's over reads
/// [AudaxRegistrationStatus.closed] even when its close date is still ahead,
/// and "closed" beside a future date would be nonsense.
bool audaxDateHasPassed(DateTime date, {DateTime? now}) =>
    _dateOnly(date).isBefore(_dateOnly(now ?? DateTime.now()));

const _openColor = Color(0xFF43A047); // green
const _closedColor = Color(0xFFE53935); // red
const _tbaColor = Color(0xFF9E9E9E); // grey

Color _statusColor(AudaxRegistrationStatus status) => switch (status) {
      AudaxRegistrationStatus.open => _openColor,
      AudaxRegistrationStatus.closed => _closedColor,
      AudaxRegistrationStatus.tba => _tbaColor,
    };

String _statusLabel(AudaxRegistrationStatus status) => switch (status) {
      AudaxRegistrationStatus.open => 'Open',
      AudaxRegistrationStatus.closed => 'Closed',
      AudaxRegistrationStatus.tba => 'TBA',
    };

/// Spoken form of the badge. "Open" alone is ambiguous read aloud next to the
/// category pill — what's open isn't on screen for a screen reader user.
String _statusSemantics(AudaxRegistrationStatus status) => switch (status) {
      AudaxRegistrationStatus.open => 'Registration open',
      AudaxRegistrationStatus.closed => 'Registration closed',
      AudaxRegistrationStatus.tba => 'Registration date to be announced',
    };

/// A small pill reading Open/Closed/TBA, shaped to match
/// [AudaxCategoryBadge] so the two sit together as one unit in the card
/// header. Colour is a second signal, not the only one — the label carries the
/// meaning on its own.
class AudaxRegistrationBadge extends StatelessWidget {
  final AudaxRegistrationStatus status;

  const AudaxRegistrationBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final seed = _statusColor(status);
    return Semantics(
      label: _statusSemantics(status),
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: audaxBadgeFill(context, seed),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _statusLabel(status),
            style: TextStyle(
              color: audaxBadgeInk(context, seed),
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
