import 'package:flutter_test/flutter_test.dart';
import 'package:mhbuddy_web/l10n.dart';

void main() {
  test('four locales share every key', () {
    L10n.check();
    final hans = L10n('zh-Hans');
    for (final key in L10n.tables.keys) {
      for (final code in L10n.codes) {
        expect(L10n(code).t(key), isNotEmpty);
      }
      expect(hans.t(key), isNot(key));
    }
  });
}
