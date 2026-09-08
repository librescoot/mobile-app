import 'package:flutter_test/flutter_test.dart';
import 'package:unustasis/service/ble_commands.dart';

void main() {
  group('checkApn', () {
    test('accepts a plain operator APN', () {
      expect(checkApn('internet'), isNull);
      expect(checkApn('web.vodafone.de'), isNull);
      expect(checkApn('internet.t-mobile'), isNull);
      expect(checkApn('m2m_internet'), isNull);
    });

    test('rejects an empty APN', () {
      expect(checkApn(''), ApnProblem.empty);
    });

    test('rejects inner whitespace and tabs', () {
      expect(checkApn('two words'), ApnProblem.invalidCharacters);
      expect(checkApn('tab\there'), ApnProblem.invalidCharacters);
    });

    test('rejects non-ASCII, which the command characteristic cannot carry', () {
      expect(checkApn('süd.example'), ApnProblem.invalidCharacters);
      expect(checkApn('интернет'), ApnProblem.invalidCharacters);
    });

    test('accepts an APN of exactly the maximum length', () {
      expect(checkApn('a' * maxApnLength), isNull);
    });

    test('rejects an APN one character over the maximum', () {
      expect(checkApn('a' * (maxApnLength + 1)), ApnProblem.tooLong);
    });

    test('leaves room for the command prefix inside one extended write', () {
      // The whole "config:apn <value>" write has to fit the extended command
      // budget, so the cap can't be the 100 octets 3GPP allows for an APN.
      expect('config:apn ${'a' * maxApnLength}'.length, lessThanOrEqualTo(100));
    });

    test('the command prefix keeps its trailing space', () {
      // clearCellularApnCommand sends the bare prefix to set an empty value.
      // The firmware splits the payload on the first space and answers
      // config:error:missing value when there is no second field, so dropping
      // that space would turn "clear" into an error with nothing to show for
      // it. maxApnLength is derived from the prefix length, which pins it.
      expect(100 - maxApnLength, 'config:apn '.length);
    });
  });
}
