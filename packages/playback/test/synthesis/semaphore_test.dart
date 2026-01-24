import 'package:flutter_test/flutter_test.dart';
import 'package:playback/src/synthesis/semaphore.dart';

void main() {
  group('Semaphore', () {
    test('allows up to maxCount concurrent operations', () async {
      final semaphore = Semaphore(2);
      expect(semaphore.available, 2);
      expect(semaphore.activeCount, 0);

      await semaphore.acquire();
      expect(semaphore.available, 1);
      expect(semaphore.activeCount, 1);

      await semaphore.acquire();
      expect(semaphore.available, 0);
      expect(semaphore.activeCount, 2);

      semaphore.release();
      expect(semaphore.available, 1);

      semaphore.release();
      expect(semaphore.available, 2);
    });

    test('tryAcquire returns false when no slots available', () async {
      final semaphore = Semaphore(1);

      expect(semaphore.tryAcquire(), isTrue);
      expect(semaphore.available, 0);

      expect(semaphore.tryAcquire(), isFalse);
      expect(semaphore.activeCount, 1);

      semaphore.release();
      expect(semaphore.tryAcquire(), isTrue);
    });

    test('waiters are served FIFO', () async {
      final semaphore = Semaphore(1);
      final order = <int>[];

      await semaphore.acquire(); // Take the only slot

      // Queue up waiters
      final waiter1 = semaphore.acquire().then((_) => order.add(1));
      final waiter2 = semaphore.acquire().then((_) => order.add(2));
      final waiter3 = semaphore.acquire().then((_) => order.add(3));

      // Release slots one at a time
      semaphore.release();
      await waiter1;
      semaphore.release();
      await waiter2;
      semaphore.release();
      await waiter3;

      expect(order, [1, 2, 3]);
    });

    test('withPermit executes action and releases', () async {
      final semaphore = Semaphore(1);
      var executed = false;

      await semaphore.withPermit(() async {
        expect(semaphore.activeCount, 1);
        executed = true;
        return 'result';
      });

      expect(executed, isTrue);
      expect(semaphore.activeCount, 0);
    });

    test('withPermit releases on exception', () async {
      final semaphore = Semaphore(1);

      try {
        await semaphore.withPermit(() async {
          throw Exception('test error');
        });
      } catch (e) {
        // Expected
      }

      expect(semaphore.activeCount, 0);
      expect(semaphore.available, 1);
    });
  });
}
