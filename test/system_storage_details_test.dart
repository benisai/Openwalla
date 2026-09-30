import 'package:flutter_test/flutter_test.dart';
import 'package:openwalla/state/app_state.dart';

void main() {
  test('prioritizes overlay and temporary storage mounts', () {
    const overlay = SystemStorageMount(
      device: '/dev/ubi0_3',
      mountPath: '/overlay',
      totalBytes: 100,
      freeBytes: 75,
    );
    const temp = SystemStorageMount(
      device: 'tmpfs',
      mountPath: '/tmp',
      totalBytes: 200,
      freeBytes: 150,
    );
    const root = SystemStorageMount(
      device: '/dev/root',
      mountPath: '/',
      totalBytes: 300,
      freeBytes: 0,
    );
    const details = SystemStorageDetails(mounts: [root, temp, overlay]);

    expect(details.primaryMounts, [overlay, temp]);
    expect(overlay.usedBytes, 25);
    expect(overlay.usedFraction, 0.25);
  });

  test('uses root storage when overlay is not separately mounted', () {
    const root = SystemStorageMount(
      device: 'overlayfs:/overlay',
      mountPath: '/',
      totalBytes: 100,
      freeBytes: 40,
    );
    const details = SystemStorageDetails(mounts: [root]);

    expect(details.userMount, root);
    expect(details.primaryMounts, [root]);
  });

  test(
    'aggregates persistent storage without duplicate or temporary mounts',
    () {
      const overlay = SystemStorageMount(
        device: '/dev/ubi0_3',
        mountPath: '/overlay',
        totalBytes: 100,
        freeBytes: 75,
      );
      const root = SystemStorageMount(
        device: 'overlayfs:/overlay',
        mountPath: '/',
        totalBytes: 100,
        freeBytes: 75,
      );
      const temp = SystemStorageMount(
        device: 'tmpfs',
        mountPath: '/tmp',
        totalBytes: 200,
        freeBytes: 150,
      );
      const external = SystemStorageMount(
        device: '/dev/sda1',
        mountPath: '/mnt/usb',
        totalBytes: 400,
        freeBytes: 300,
      );
      const details = SystemStorageDetails(
        mounts: [root, overlay, temp, external],
      );

      expect(details.persistentMounts, [overlay, external]);
      expect(details.totalBytes, 500);
      expect(details.usedBytes, 125);
      expect(details.freeBytes, 375);
      expect(details.usedFraction, 0.25);
    },
  );
}
