import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/fake_pars_repository.dart';

void main() {
  test('fake repository accepts PGP and SSH key deletion', () async {
    const repository = FakeParsRepository();

    await repository.deletePgpKey(
      '3A8E 9C12 77FA 22D1 90BD 48AA A991 D3B4 A702 91EF',
    );
    await repository.deleteSshKey('github-mobile-ed25519');
  });
}
