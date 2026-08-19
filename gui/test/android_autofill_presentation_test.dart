import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android Autofill uses an app-owned RemoteViews-safe layout', () {
    final activity =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/autofill/'
          'ParsAutofillUnlockActivity.kt',
        ).readAsStringSync();
    final layout =
        File(
          'android/app/src/main/res/layout/pars_autofill_presentation.xml',
        ).readAsStringSync();

    expect(activity, contains('R.layout.pars_autofill_presentation'));
    expect(activity, isNot(contains('android.R.layout.simple_list_item_2')));
    expect(layout, contains('<LinearLayout'));
    expect(layout, contains('<TextView'));
    expect(layout, isNot(contains('TwoLineListItem')));
  });

  test('empty candidate queries return a visible no-match response', () {
    final service =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/autofill/'
          'ParsAutofillService.kt',
        ).readAsStringSync();

    expect(
      service,
      contains(
        'if (candidates.isEmpty()) {\n'
        '            callback.onSuccess(noMatchesResponse(parsed))',
      ),
    );
    expect(
      service,
      contains('.setAuthentication(ids, authentication, presentation)'),
    );
    expect(
      service,
      isNot(
        contains(
          'if (candidates.isEmpty()) {\n'
          '            callback.onSuccess(null)',
        ),
      ),
    );
  });
}
