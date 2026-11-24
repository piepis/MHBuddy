import 'package:flutter_test/flutter_test.dart';
import 'package:mhbuddy_web/time_format.dart';

void main() {
  test('event instants render as a local clock without a Z suffix', () {
    final text = formatEventInstant('2026-11-23T00:00:00Z');
    expect(text.contains('T'), isFalse);
    expect(text.contains('Z'), isFalse);
    expect(text, contains('2026-11-23'));
  });

  test('event progress follows the start and end', () {
    expect(eventProgress('2026-11-23T00:00:00Z', '2026-11-30T16:00:00Z', DateTime.utc(2026, 11, 23)), 0);
    final mid = eventProgress('2026-11-23T00:00:00Z', '2026-11-25T00:00:00Z', DateTime.utc(2026, 11, 24));
    expect(mid, closeTo(0.5, 0.02));
    expect(eventProgress('2026-11-23T00:00:00Z', '2026-11-25T00:00:00Z', DateTime.utc(2026, 11, 26)), 1);
  });
}
