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
}
