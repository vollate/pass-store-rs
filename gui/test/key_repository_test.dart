import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';
import 'package:pars_gui/services/key_repository.dart';

void main() {
  test('recipient matching mirrors bridge fingerprint and identity rules', () {
    expect(
      pgpIdentityMatchesRecipient(
        fingerprint: '0000 ABCD',
        identity: 'Alice <alice@example.com>',
        recipient: 'ABCD',
      ),
      isTrue,
    );
    expect(
      pgpIdentityMatchesRecipient(
        fingerprint: '0000 ABCD',
        identity: 'Alice <alice@example.com>',
        recipient: 'alice@example.com',
      ),
      isTrue,
    );
    expect(
      pgpIdentityMatchesRecipient(
        fingerprint: 'ABCD',
        identity: 'Mallory alice@example.com',
        recipient: 'alice@example.com',
      ),
      isFalse,
    );
    expect(
      pgpIdentityMatchesRecipient(
        fingerprint: 'ABCD',
        identity: 'Alice',
        recipient: '0000ABCD',
      ),
      isFalse,
    );
  });

  test(
    'fake repository supports contextual recipients and SSH deletion',
    () async {
      const repository = FakeParsRepository();

      await repository.initializeStoreRecipients(const <String>['ABCD']);
      await repository.deleteSshKey('github-mobile-ed25519');
    },
  );
}
