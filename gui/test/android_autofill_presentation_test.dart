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

  test('Autofill unlock presentation consumes localized resources', () {
    final activity =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/autofill/'
          'ParsAutofillUnlockActivity.kt',
        ).readAsStringSync();

    for (final resource in <String>[
      'R.string.autofill_unlock_title',
      'R.string.autofill_unlock_subtitle',
      'R.string.autofill_cancel',
      'R.string.autofill_password_source',
    ]) {
      expect(activity, contains(resource));
    }
    expect(activity, isNot(contains('.setTitle("Unlock Pars")')));
    expect(activity, isNot(contains('"Fill the selected password"')));
    expect(activity, isNot(contains('"Pars password"')));
    final service =
        File(
          'android/app/src/main/kotlin/top/vollate/pars_gui/autofill/'
          'ParsAutofillService.kt',
        ).readAsStringSync();
    expect(service, contains('R.string.autofill_candidate_title'));
  });

  test('iOS credential provider consumes its localized auth reason', () {
    final controller =
        File(
          'ios/ParsCredentialProvider/CredentialProviderViewController.swift',
        ).readAsStringSync();

    expect(controller, contains('NSLocalizedString('));
    expect(controller, contains('autofill_authentication_reason'));
    expect(
      controller,
      isNot(contains('localizedReason: "Unlock Pars to fill this password"')),
    );
  });

  test(
    'authentication PendingIntents have collision-resistant one-shot identity',
    () {
      final activity =
          File(
            'android/app/src/main/kotlin/top/vollate/pars_gui/autofill/'
            'ParsAutofillUnlockActivity.kt',
          ).readAsStringSync();

      expect(activity, contains('UUID.randomUUID().toString()'));
      expect(activity, contains('.scheme("pars-autofill")'));
      expect(activity, contains('PendingIntent.FLAG_ONE_SHOT'));
    },
  );

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
