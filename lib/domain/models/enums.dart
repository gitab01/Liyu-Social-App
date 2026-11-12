/// Value types shared across the domain model.
///
/// These map directly onto Firestore field values, so the wire format and the
/// in-memory format stay identical between the local and Firebase backends.
library;

enum Audience {
  /// Visible to any authenticated reader.
  everyone,

  /// Visible to the author and their followers only.
  followers;

  static Audience parse(String? raw) => switch (raw) {
    'followers' => Audience.followers,
    _ => Audience.everyone,
  };
}

/// Delivery state of an outgoing message. `pending` and `failed` are rendered
/// distinctly so a send is never presented as successful before the backend
/// acknowledges it.
enum MessageStatus {
  pending,
  sent,
  failed;

  static MessageStatus parse(String? raw) => switch (raw) {
    'pending' => MessageStatus.pending,
    'failed' => MessageStatus.failed,
    _ => MessageStatus.sent,
  };
}

enum NotificationType {
  mention,
  message,
  like,
  comment,
  follow;

  static NotificationType parse(String? raw) => NotificationType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => NotificationType.like,
  );
}

/// Lifecycle of an offline write handed to the queue.
enum PendingWriteState { queued, inFlight, delivered, rejected }
