import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/models.dart';

void main() {
  test('family member maps persisted role and timestamp', () {
    final member = FamilyMember.fromMap({
      'id': 3,
      'name': '爸爸',
      'role': 'owner',
      'created_at': '2026-09-30T22:30:00.000',
    });

    expect(member.name, '爸爸');
    expect(member.role, 'owner');
    expect(member.createdAt.year, 2026);
  });

  test('sync profile requires all connection fields', () {
    const incomplete = SyncProfile(
      serverUrl: 'http://192.168.1.20:8787',
      familyId: '',
      token: 'token',
      revision: 0,
    );
    const complete = SyncProfile(
      serverUrl: 'http://192.168.1.20:8787',
      familyId: 'family123',
      token: 'token',
      revision: 4,
    );

    expect(incomplete.isConfigured, isFalse);
    expect(complete.isConfigured, isTrue);
    expect(complete.revision, 4);
  });
}
