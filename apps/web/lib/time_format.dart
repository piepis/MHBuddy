String formatEventInstant(Object? raw) {
  final parsed = DateTime.tryParse('${raw ?? ''}');
  if (parsed == null) return '${raw ?? ''}';
  final local = parsed.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

double eventProgress(Object? start, Object? end, DateTime now) {
  final a = DateTime.tryParse('${start ?? ''}');
  final b = DateTime.tryParse('${end ?? ''}');
  if (a == null || b == null || !b.isAfter(a)) return 0;
  final clock = now.toUtc();
  if (clock.isBefore(a.toUtc())) return 0;
  if (!clock.isBefore(b.toUtc())) return 1;
  return clock.difference(a.toUtc()).inMilliseconds / b.toUtc().difference(a.toUtc()).inMilliseconds;
}
