/// Compact counts for profile and post stats. Feed rows render these on every
/// tile, so they stay short and locale-aware rather than full-length numbers.
String compactCount(int value, {String languageCode = 'en'}) {
  final am = languageCode == 'am';

  String trim(double n) {
    final s = n >= 100 ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  if (value < 1000) return '$value';
  if (value < 1000000) return '${trim(value / 1000)}${am ? 'ሺ' : 'K'}';
  if (value < 1000000000) return '${trim(value / 1000000)}${am ? 'ሚ' : 'M'}';
  return '${trim(value / 1000000000)}${am ? 'ቢ' : 'B'}';
}

/// "now" / "5m" / "3h" / "2d" — feed timestamps are read hundreds of times per
/// session, so a two-character form beats a full date. Older than a week falls
/// back to an absolute date.
String relativeTime(DateTime moment, String languageCode, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final diff = at.difference(moment);
  final am = languageCode == 'am';

  if (diff.isNegative || diff.inSeconds < 45) return am ? 'አሁን' : 'now';
  if (diff.inMinutes < 60) return am ? '${diff.inMinutes} ደቂቃ' : '${diff.inMinutes}m';
  if (diff.inHours < 24) return am ? '${diff.inHours} ሰዓት' : '${diff.inHours}h';
  if (diff.inDays < 7) return am ? '${diff.inDays} ቀን' : '${diff.inDays}d';
  return absoluteDate(moment, languageCode);
}

String absoluteDate(DateTime moment, String languageCode) {
  const monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const monthsAm = ['ጃንዋሪ', 'የካቲት', 'መጋቢት', 'ኤፕሪል', 'ሜይ', 'ጁን', 'ጁላይ', 'ኦገስት', 'ሴፕቴምበር', 'ኦክቶበር', 'ኖቬምበር', 'ዲሴምበር'];
  final months = languageCode == 'am' ? monthsAm : monthsEn;
  final year = languageCode == 'am' ? ' ${moment.year}' : ' ${moment.year}';
  return '${moment.day} ${months[monthIndex(moment)]}$year';
}

int monthIndex(DateTime moment) => moment.month - 1;

/// Clock form used inside a chat thread, where the day matters less than the
/// minute.
String clockTime(DateTime moment) {
  final hour = moment.hour % 12 == 0 ? 12 : moment.hour % 12;
  final minute = moment.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${moment.hour < 12 ? 'AM' : 'PM'}';
}

/// Data cost is the metric this app is designed around, so the composer shows
/// the bytes it saved in the unit a metered user thinks in.
String formatBytes(int? bytes, {String languageCode = 'en'}) {
  if (bytes == null) return '—';
  const kb = 1024;
  const mb = kb * 1024;
  final am = languageCode == 'am';
  if (bytes < kb) return '$bytes B';
  if (bytes < mb) {
    final v = bytes / kb;
    return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${am ? 'ኪባ' : 'KB'}';
  }
  final v = bytes / mb;
  return '${v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)} ${am ? 'ሜባ' : 'MB'}';
}

/// 0..1 as the percentage a progress ring needs.
String percent(double fraction) => '${(fraction.clamp(0, 1) * 100).round()}%';
