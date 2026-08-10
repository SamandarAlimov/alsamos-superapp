import 'package:alsamos_flutter/shared/stories/story_presence_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('batches concurrent ring requests and reuses cached presence', () async {
    var calls = 0;
    Set<String>? requestedIds;
    final controller = StoryPresenceController(
      batchDelay: Duration.zero,
      loader: (userIds) async {
        calls++;
        requestedIds = Set<String>.from(userIds);
        return {
          for (final userId in userIds)
            userId: const StoryAvatarRingState(
              hasActiveStory: true,
              allViewed: false,
            ),
        };
      },
    );
    addTearDown(controller.dispose);

    final values = await Future.wait([
      controller.load('user-a'),
      controller.load('user-b'),
    ]);

    expect(calls, 1);
    expect(requestedIds, {'user-a', 'user-b'});
    expect(values.every((value) => value.hasActiveStory), isTrue);

    await controller.load('user-a');
    expect(calls, 1);
  });

  test('invalidating one user refreshes only that presence entry', () async {
    var calls = 0;
    final controller = StoryPresenceController(
      batchDelay: Duration.zero,
      loader: (userIds) async {
        calls++;
        return {
          for (final userId in userIds)
            userId: StoryAvatarRingState(
              hasActiveStory: calls.isOdd,
              allViewed: false,
            ),
        };
      },
    );
    addTearDown(controller.dispose);

    expect((await controller.load('user-a')).hasActiveStory, isTrue);
    controller.invalidateUser('user-a');
    expect((await controller.load('user-a')).hasActiveStory, isFalse);
    expect(calls, 2);
  });

  test('seeded presence is available without a network load', () async {
    var calls = 0;
    final controller = StoryPresenceController(
      loader: (userIds) async {
        calls++;
        return const {};
      },
    );
    addTearDown(controller.dispose);

    controller.seed(
      userId: 'user-a',
      hasActiveStory: true,
      allViewed: true,
    );
    final value = await controller.load('user-a');

    expect(value.hasActiveStory, isTrue);
    expect(value.allViewed, isTrue);
    expect(calls, 0);
  });
}
