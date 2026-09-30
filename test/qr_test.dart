import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/qr.dart';

void main() {
  test('location code is stable and padded', () {
    expect(locationCodeFromId(12), 'FHM-LOC-000012');
  });

  test('QR payload round trips', () {
    const code = 'FHM-LOC-000123';
    final payload = buildLocationQrPayload(code);
    expect(payload, 'fhm://location/FHM-LOC-000123');
    expect(parseLocationQrPayload(payload), code);
  });

  test('plain location code is also accepted', () {
    expect(
      parseLocationQrPayload('FHM-LOC-000002'),
      'FHM-LOC-000002',
    );
  });

  test('foreign QR is rejected', () {
    expect(parseLocationQrPayload('https://example.com'), isNull);
  });
}
