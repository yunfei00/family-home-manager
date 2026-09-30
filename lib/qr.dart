const String locationQrPrefix = 'fhm://location/';

String locationCodeFromId(int id) {
  return 'FHM-LOC-' + id.toString().padLeft(6, '0');
}

String buildLocationQrPayload(String code) {
  return locationQrPrefix + code;
}

String? parseLocationQrPayload(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;

  if (value.startsWith(locationQrPrefix)) {
    final code = value.substring(locationQrPrefix.length).trim();
    return code.isEmpty ? null : code;
  }

  if (value.startsWith('FHM-LOC-')) {
    return value;
  }

  return null;
}
