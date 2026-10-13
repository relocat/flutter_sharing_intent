// SPDX-License-Identifier: Apache-2.0
// Modified by Relocat (2026); see NOTICE.
import 'package:flutter_sharing_intent/model/sharing_file.dart';
import 'package:flutter_test/flutter_test.dart';

// Tests for FSI-94: SharedFile.fromJson must not crash on out-of-range
// or non-integer 'type' values from an attacker-controlled EventChannel payload.
void main() {
  group('SharedFile.fromJson type field guard (FSI-94)', () {
    test('valid index 0 (TEXT) decodes correctly', () {
      final f = SharedFile.fromJson({'value': 'hello', 'type': 0});
      expect(f.type, SharedMediaType.TEXT);
    });

    test('valid index 4 (FILE) decodes correctly', () {
      final f = SharedFile.fromJson({'value': 'a.pdf', 'type': 4});
      expect(f.type, SharedMediaType.FILE);
    });

    test('last valid index (OTHER = 6) decodes correctly', () {
      final f = SharedFile.fromJson({'value': 'x', 'type': 6});
      expect(f.type, SharedMediaType.OTHER);
    });

    test('out-of-range positive index falls back to FILE', () {
      // Index 99 is well beyond the enum length; must not throw RangeError.
      final f = SharedFile.fromJson({'value': 'x', 'type': 99});
      expect(f.type, SharedMediaType.FILE);
    });

    test('negative index falls back to FILE', () {
      final f = SharedFile.fromJson({'value': 'x', 'type': -1});
      expect(f.type, SharedMediaType.FILE);
    });

    test('non-int type falls back to TEXT (index 0)', () {
      // raw is a String, not an int => typeIdx defaults to 0 => TEXT.
      // Verify it doesn't crash and returns the index-0 value (TEXT).
      final f = SharedFile.fromJson({'value': 'x', 'type': 'image'});
      expect(f.type, SharedMediaType.TEXT);
    });

    test('null type falls back to TEXT (index 0)', () {
      final f = SharedFile.fromJson({'value': 'x', 'type': null});
      expect(f.type, SharedMediaType.TEXT);
    });

    test('missing type key falls back to TEXT (index 0)', () {
      final f = SharedFile.fromJson({'value': 'x'});
      expect(f.type, SharedMediaType.TEXT);
    });
  });
}
