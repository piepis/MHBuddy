import 'package:flutter_test/flutter_test.dart';
import 'package:mhbuddy_web/l10n.dart';

void main() {
  test('locale tables are complete', () {
    L10n.check();
    expect(L10n.codes, hasLength(4));
  });
}
