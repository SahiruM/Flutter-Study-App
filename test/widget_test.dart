import 'package:flutter_test/flutter_test.dart';
import 'package:studyapp/main.dart';

void main() {
  test('timer clock formatting matches the website timer', () {
    expect(formatClock(0), '00:00:00');
    expect(formatClock(65), '00:01:05');
    expect(formatClock(3661), '01:01:01');
  });

  test('sessions are stored locally before any sync happens', () {
    final state = AppState.initial().addSessionRange(
      '1',
      DateTime(2026, 5, 3, 10),
      DateTime(2026, 5, 3, 10, 2, 5),
    );

    expect(state.sessions, hasLength(1));
    expect(state.sessions.first.taskId, '1');
    expect(state.sessions.first.duration, 125);
  });

  test('sessions crossing midnight are split across both days', () {
    final state = AppState.initial().addSessionRange(
      '1',
      DateTime(2026, 5, 3, 23, 30),
      DateTime(2026, 5, 4, 0, 30),
    );

    expect(state.sessions, hasLength(2));
    expect(state.sessions[0].date, '2026-05-03');
    expect(state.sessions[0].duration, 30 * 60);
    expect(state.sessions[1].date, '2026-05-04');
    expect(state.sessions[1].duration, 30 * 60);
  });

  test('unicorn feed state is stored with app state', () {
    final state = AppState.initial().copyWith(
      unicorn: UnicornState(
        feedDate: '2026-05-05',
        fedRainbows: 2,
        updatedAt: DateTime(2026, 5, 5, 10),
      ),
    );

    final restored = AppState.fromJson(state.toJson());

    expect(restored.unicorn.feedDate, '2026-05-05');
    expect(restored.unicorn.fedRainbows, 2);
  });

  test('unicorn feed merge keeps the newest device state', () {
    final local = AppState.initial().copyWith(
      unicorn: UnicornState(
        feedDate: '2026-05-05',
        fedRainbows: 1,
        updatedAt: DateTime(2026, 5, 5, 10),
      ),
    );
    final remote = AppState.initial().copyWith(
      unicorn: UnicornState(
        feedDate: '2026-05-05',
        fedRainbows: 3,
        updatedAt: DateTime(2026, 5, 5, 11),
      ),
    );

    final merged = local.merge(remote);

    expect(merged.unicorn.fedRainbows, 3);
  });

  test('unicorn feed state can load old rabbit sync data', () {
    final state = AppState.fromJson({
      ...AppState.initial().toJson(),
      'unicorn': null,
      'rabbit': {
        'feedDate': '2026-05-05',
        'fedCarrots': 4,
        'updatedAt': DateTime(2026, 5, 5, 12).toIso8601String(),
      },
    });

    expect(state.unicorn.feedDate, '2026-05-05');
    expect(state.unicorn.fedRainbows, 4);
  });
}
