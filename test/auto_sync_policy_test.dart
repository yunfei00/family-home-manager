import 'package:flutter_test/flutter_test.dart';
import 'package:family_home_manager/sync_state.dart';

void main() {
  test('auto sync uploads local changes on same revision', () {
    expect(
      decideAutoSync(
        configured: true,
        enabled: true,
        dirty: true,
        localRevision: 3,
        remoteRevision: 3,
      ),
      AutoSyncDecision.upload,
    );
  });

  test('auto sync downloads remote-only changes', () {
    expect(
      decideAutoSync(
        configured: true,
        enabled: true,
        dirty: false,
        localRevision: 3,
        remoteRevision: 4,
      ),
      AutoSyncDecision.download,
    );
  });

  test('auto sync never overwrites concurrent changes', () {
    expect(
      decideAutoSync(
        configured: true,
        enabled: true,
        dirty: true,
        localRevision: 3,
        remoteRevision: 4,
      ),
      AutoSyncDecision.conflict,
    );
  });

  test('auto sync respects disabled setting', () {
    expect(
      decideAutoSync(
        configured: true,
        enabled: false,
        dirty: true,
        localRevision: 3,
        remoteRevision: 3,
      ),
      AutoSyncDecision.disabled,
    );
  });

  test('server behind local revision is treated as inconsistent', () {
    expect(
      decideAutoSync(
        configured: true,
        enabled: true,
        dirty: false,
        localRevision: 5,
        remoteRevision: 4,
      ),
      AutoSyncDecision.inconsistent,
    );
  });
}
