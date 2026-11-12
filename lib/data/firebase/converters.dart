import 'package:cloud_firestore/cloud_firestore.dart';

/// The single place where domain [DateTime]s become Firestore `Timestamp`s and
/// back again.
///
/// Every model in `lib/domain/models` round-trips through `toMap()`/`fromMap()`
/// with plain Dart values, and the local backend happily stores an ISO string.
/// Firestore will not: a cursor page ordered on `createdAt` only seeks correctly
/// if the stored value is a real `Timestamp`, and a string would sort
/// lexicographically instead of chronologically. So writes pass through
/// [withTimestamps] and reads through [domainMap], and nothing in the data layer
/// hand-decodes a date anywhere else.
///
/// Only the shared timestamp fields are converted. They are the ones the domain
/// declares as instants rather than display strings — a post's `createdAt`, a
/// story's `expiresAt`, the message delivery clocks.
class TimestampFields {
  const TimestampFields._();

  /// The document fields that must be `Timestamp` in Firestore.
  static const Set<String> names = {
    'createdAt',
    'expiresAt',
    'lastMessageAt',
    'deliveredAt',
    'readAt',
  };
}

/// Turns the `DateTime` values in a model map into `Timestamp`s, ready to hand
/// to Firestore. Keys that are not timestamps — and null timestamps — pass
/// through untouched, so an absent `deliveredAt` stays absent rather than
/// becoming an epoch value.
Map<String, Object?> withTimestamps(Map<String, Object?> map) {
  final out = <String, Object?>{};
  for (final entry in map.entries) {
    final value = entry.value;
    if (TimestampFields.names.contains(entry.key) && value is DateTime) {
      out[entry.key] = Timestamp.fromDate(value);
    } else {
      out[entry.key] = value;
    }
  }
  return out;
}

/// Reads a Firestore document back into the domain shape: every timestamp field
/// that came out as a `Timestamp` (or, defensively, a raw `DateTime` from a
/// pending local write) is converted to a `DateTime` so the model's `fromMap`
/// casts succeed.
Map<String, Object?> domainMap(DocumentSnapshot<Map<String, dynamic>> snapshot) {
  final data = snapshot.data();
  if (data == null) return const {};
  final out = <String, Object?>{};
  for (final entry in data.entries) {
    final value = entry.value;
    if (TimestampFields.names.contains(entry.key)) {
      if (value is Timestamp) {
        out[entry.key] = value.toDate();
      } else {
        out[entry.key] = value;
      }
    } else {
      out[entry.key] = value;
    }
  }
  return out;
}

/// Convenience for the many `docs.map(domainMap).map(Model.fromMap)` chains:
/// project a snapshot's documents straight into domain maps.
List<Map<String, Object?>> domainMaps(QuerySnapshot<Map<String, dynamic>> snapshot) =>
    snapshot.docs.map(domainMap).toList();
