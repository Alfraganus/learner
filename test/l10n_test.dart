import 'package:flutter_test/flutter_test.dart';
import 'package:learner/l10n/strings.dart';

void main() {
  test('every UI string exists in uz, en and ru', () {
    final all = {for (final c in AppLang.codes) ...S.keysOf(c)};
    for (final c in AppLang.codes) {
      expect(all.difference(S.keysOf(c)), isEmpty, reason: 'missing in $c');
    }
  });

  test('placeholders are filled', () {
    expect(S('ru').t('err_api', {'code': 500, 'msg': 'x'}), 'Ошибка Anthropic API (500): x');
    expect(S('en').t('part_of', {'n': 2, 'm': 5}), 'Part 2 / 5');
  });
}
