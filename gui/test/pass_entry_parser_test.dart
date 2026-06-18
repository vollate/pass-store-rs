import 'package:flutter_test/flutter_test.dart';
import 'package:pars_gui/services/pass_entry_parser.dart';

void main() {
  group('PassEntryParser', () {
    test('uses the first line as password', () {
      final content = PassEntryParser.parse('hunter2');

      expect(content.password, 'hunter2');
      expect(content.fields, isEmpty);
      expect(content.rawNotes, isEmpty);
    });

    test('parses common metadata fields after first line', () {
      final content = PassEntryParser.parse(
        'hunter2\nusername: alice\nurl: https://github.com\nemail: alice@example.com',
      );

      expect(content.password, 'hunter2');
      expect(content.fieldValue('username'), 'alice');
      expect(content.fieldValue('url'), 'https://github.com');
      expect(content.fieldValue('email'), 'alice@example.com');
      expect(content.rawNotes, isEmpty);
    });

    test('preserves unknown metadata as raw notes', () {
      final content = PassEntryParser.parse(
        'hunter2\nsecurity question answer\nproject=demo',
      );

      expect(content.password, 'hunter2');
      expect(content.fields, isEmpty);
      expect(content.rawNotes, 'security question answer\nproject=demo');
    });

    test('keeps mixed known and unknown lines', () {
      final content = PassEntryParser.parse(
        'hunter2\nlogin: alice\ncreated by hand\nwebsite: https://example.com',
      );

      expect(content.fieldValue('login'), 'alice');
      expect(content.fieldValue('website'), 'https://example.com');
      expect(content.rawNotes, 'created by hand');
    });
  });
}
