import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'state_store.dart';

void main() {
  runApp(const StudyApp());
}

const _firebaseProjectId = String.fromEnvironment(
  'FIREBASE_PROJECT_ID',
  defaultValue: 'suustudy-16663',
);
const _firebaseApiKey = String.fromEnvironment(
  'FIREBASE_WEB_API_KEY',
  defaultValue: 'AIzaSyB9ksx7_HnEtWYboO3ba57CamqUf9xdVWY',
);

class StudyApp extends StatelessWidget {
  const StudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StudyBud',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const BootstrapScreen(),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9B87D6),
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF121018)
        : const Color(0xFFFFFBFE),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF1D1A24) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xFF393442) : const Color(0xFFE8E0EA),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  late final StudyRepository _repo;
  AppState? _state;

  @override
  void initState() {
    super.initState();
    _repo = StudyRepository();
    _load();
  }

  Future<void> _load() async {
    final state = await _repo.load();
    if (!mounted) return;
    setState(() => _state = state);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StudyHome(repository: _repo, initialState: state);
  }
}

class StudyHome extends StatefulWidget {
  const StudyHome({
    required this.repository,
    required this.initialState,
    super.key,
  });

  final StudyRepository repository;
  final AppState initialState;

  @override
  State<StudyHome> createState() => _StudyHomeState();
}

class _StudyHomeState extends State<StudyHome> with WidgetsBindingObserver {
  late AppState _state;
  Timer? _ticker;
  Timer? _syncDebounce;
  bool _isSyncing = false;
  bool _showAuth = false;
  bool _isDark = false;
  bool _focusMode = false;
  String? _syncError;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState.withRecomputedTimer();
    _isDark = _state.isDark;
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
    _attemptSync(preferRemote: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _syncDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _attemptSync(preferRemote: true);
    }
  }

  String get _syncStatusText {
    if (_state.auth == null) return 'offline ready';
    if (_isSyncing) return 'syncing...';
    if (_syncError != null) return 'sync failed';
    if (_state.hasPendingSync) return 'waiting to sync';
    return 'synced';
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final timerActive = _state.timer.isRunning && !_state.timer.isPaused;
      final countdownActive = _state.countdown.isRunning;
      if (!timerActive && !countdownActive) return;
      final wasCountdownRunning = _state.countdown.isRunning;
      var next = _state.withRecomputedTimer();
      if (wasCountdownRunning && !next.countdown.isRunning) {
        next = next.touch();
      }
      setState(() => _state = next);
      if (wasCountdownRunning && !next.countdown.isRunning) {
        _save();
      }
    });
  }

  Future<void> _save({bool sync = true}) async {
    await widget.repository.save(_state);
    if (!sync || _state.auth == null) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 500), _attemptSync);
  }

  Future<void> _attemptSync({
    bool showFeedback = false,
    bool preferRemote = false,
  }) async {
    if (_isSyncing || _state.auth == null) return;
    setState(() {
      _isSyncing = true;
      _syncError = null;
    });
    try {
      final synced = await widget.repository.sync(
        _state,
        preferRemote: preferRemote,
      );
      if (!mounted) return;
      setState(() {
        _state = synced.withRecomputedTimer();
        _isDark = _state.isDark;
        _isSyncing = false;
        _syncError = null;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sync complete')));
      }
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _state = _state.copyWith(hasPendingSync: true);
        _isSyncing = false;
        _syncError = message;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  StudyTask? get _activeTask {
    for (final task in _state.tasks) {
      if (task.id == _state.activeTaskId) return task;
    }
    return _state.tasks.isEmpty ? null : _state.tasks.first;
  }

  void _update(AppState Function(AppState state) change) {
    setState(() => _state = change(_state).touch());
    _save();
  }

  Future<void> _signIn(
    String name,
    String email,
    String password,
    bool signUp,
  ) async {
    final result = await widget.repository.authenticate(
      name,
      email,
      password,
      signUp,
    );
    if (!mounted) return;
    final loaded = await widget.repository.loadForAuth(result);
    if (!mounted) return;
    setState(() {
      _state = loaded.withRecomputedTimer();
      _isDark = _state.isDark;
      _showAuth = false;
      _syncError = null;
    });
    await _attemptSync(preferRemote: true);
  }

  Future<void> _logout() async {
    await widget.repository.logout();
    if (!mounted) return;
    setState(() {
      _state = AppState.initial();
      _showAuth = true;
      _syncError = null;
    });
  }

  void _toggleTheme() {
    _update((state) => state.copyWith(isDark: !state.isDark));
    setState(() => _isDark = !_isDark);
  }

  void _addTask(String name) {
    final colors = ['#9b87d6', '#a8d5ff', '#ffb3c6', '#b8e6d5', '#ffd4e5'];
    _update((state) {
      final task = StudyTask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        colorHex: colors[state.tasks.length % colors.length],
        updatedAt: DateTime.now(),
      );
      return state.copyWith(
        tasks: [...state.tasks, task],
        activeTaskId: state.activeTaskId ?? task.id,
      );
    });
  }

  Future<void> _deleteTask(String id) async {
    _update((state) {
      final tasks = state.tasks.where((task) => task.id != id).toList();
      return state.copyWith(
        tasks: tasks,
        activeTaskId: state.activeTaskId == id
            ? (tasks.isEmpty ? null : tasks.first.id)
            : state.activeTaskId,
      );
    });
  }

  Future<void> _selectTask(String id) async {
    if (id == _state.activeTaskId) return;
    var next = _state;
    final currentTimer = next.timer.recompute();
    if (currentTimer.isRunning &&
        currentTimer.elapsedSeconds > 0 &&
        next.activeTaskId != null) {
      next = next.addSessionFromTimer(next.activeTaskId!, currentTimer);
    }
    final running = currentTimer.isRunning;
    final now = DateTime.now();
    next = next.copyWith(
      activeTaskId: id,
      timer: StudyTimerState(
        isRunning: running,
        isPaused: false,
        startedAt: running ? now : null,
        startTime: running ? now : null,
        elapsedBeforePause: 0,
        elapsedSeconds: 0,
        updatedAt: now,
      ),
    );
    setState(() => _state = next.touch());
    await _save();
  }

  void _startTimer() {
    final task = _activeTask;
    if (task == null) return;
    final now = DateTime.now();
    _update(
      (state) => state.copyWith(
        activeTaskId: task.id,
        timer: StudyTimerState(
          isRunning: true,
          isPaused: false,
          startedAt: now,
          startTime: now,
          elapsedBeforePause: 0,
          elapsedSeconds: 0,
          updatedAt: now,
        ),
      ),
    );
  }

  void _pauseTimer() {
    _update((state) {
      final timer = state.timer.recompute();
      final next = state.activeTaskId == null
          ? state
          : state.addSessionFromTimer(state.activeTaskId!, timer);
      return next.copyWith(
        timer: timer.copyWith(
          isPaused: true,
          elapsedBeforePause: timer.elapsedSeconds,
          startTime: null,
          updatedAt: DateTime.now(),
        ),
      );
    });
  }

  void _resumeTimer() {
    _update(
      (state) => state.copyWith(
        timer: state.timer.copyWith(
          isPaused: false,
          startTime: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  void _stopTimer() {
    _update((state) {
      var next = state;
      final timer = state.timer.recompute();
      if (timer.isRunning &&
          state.activeTaskId != null &&
          timer.elapsedSeconds > 0) {
        next = next.addSessionFromTimer(state.activeTaskId!, timer);
      }
      return next.copyWith(timer: StudyTimerState.empty());
    });
  }

  void _startCountdown() {
    _update((state) => state.copyWith(countdown: state.countdown.start()));
  }

  void _stopCountdown() {
    _update((state) => state.copyWith(countdown: state.countdown.stop()));
  }

  void _setCountdownMinutes(int minutes) {
    _update(
      (state) => state.copyWith(
        countdown: state.countdown.copyWith(
          minutes: minutes.clamp(1, 120),
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _theme(_isDark ? Brightness.dark : Brightness.light),
      child: Builder(
        builder: (context) {
          if (_showAuth || _state.auth == null) {
            return AuthScreen(onSubmit: _signIn);
          }
          if (_focusMode) {
            return FocusTimerScreen(
              task: _activeTask,
              timer: _state.timer,
              onExit: () => setState(() => _focusMode = false),
              onStart: _startTimer,
              onPause: _pauseTimer,
              onResume: _resumeTimer,
              onStop: _stopTimer,
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF9B87D6), Color(0xFFA8D5FF)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('StudyBud'),
                      Text(
                        _syncStatusText,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Sync now',
                  onPressed: _state.auth == null
                      ? null
                      : () => _attemptSync(
                          showFeedback: true,
                          preferRemote: true,
                        ),
                  icon: const Icon(Icons.cloud_sync_outlined),
                ),
                IconButton(
                  tooltip: 'Toggle theme',
                  onPressed: _toggleTheme,
                  icon: Icon(_isDark ? Icons.light_mode : Icons.dark_mode),
                ),
                IconButton(
                  tooltip: _state.auth == null ? 'Login' : 'Logout',
                  onPressed: _state.auth == null
                      ? () => setState(() => _showAuth = true)
                      : _logout,
                  icon: Icon(_state.auth == null ? Icons.login : Icons.logout),
                ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 960;
                  final left = Column(
                    children: [
                      TaskListCard(
                        tasks: _state.tasks,
                        activeTaskId: _state.activeTaskId,
                        onSelect: _selectTask,
                        onAdd: _addTask,
                        onDelete: _deleteTask,
                      ),
                      const SizedBox(height: 16),
                      CountdownCard(
                        minutes: _state.countdown.minutes,
                        secondsLeft: _state.countdown.secondsLeft,
                        isRunning: _state.countdown.isRunning,
                        onMinutesChanged: _setCountdownMinutes,
                        onStart: _startCountdown,
                        onStop: _stopCountdown,
                      ),
                    ],
                  );
                  final right = Column(
                    children: [
                      TimerCard(
                        task: _activeTask,
                        timer: _state.timer,
                        onStart: _startTimer,
                        onPause: _pauseTimer,
                        onResume: _resumeTimer,
                        onStop: _stopTimer,
                        onFocus: () => setState(() => _focusMode = true),
                      ),
                      const SizedBox(height: 16),
                      StatsSection(
                        sessions: _state.sessions,
                        tasks: _state.tasks,
                      ),
                    ],
                  );

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 320, child: left),
                                    const SizedBox(width: 18),
                                    Expanded(child: right),
                                  ],
                                )
                              : Column(
                                  children: [
                                    right,
                                    const SizedBox(height: 16),
                                    left,
                                  ],
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.onSubmit, this.onSkip, super.key});

  final Future<void> Function(
    String name,
    String email,
    String password,
    bool signUp,
  )
  onSubmit;
  final VoidCallback? onSkip;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        _name.text.trim(),
        _email.text.trim(),
        _password.text,
        _signUp,
      );
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.favorite, size: 68, color: Color(0xFFFF8FB3)),
              const SizedBox(height: 12),
              Text(
                _signUp ? 'Join StudyBud' : 'Welcome back',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      if (_signUp) ...[
                        TextField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _email,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(_signUp ? Icons.person_add : Icons.login),
                        label: Text(_signUp ? 'Create Account' : 'Login'),
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => setState(() => _signUp = !_signUp),
                        child: Text(
                          _signUp
                              ? 'Already have an account?'
                              : 'Need an account?',
                        ),
                      ),
                      if (widget.onSkip != null)
                        TextButton(
                          onPressed: widget.onSkip,
                          child: const Text('Use offline for now'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TaskListCard extends StatefulWidget {
  const TaskListCard({
    required this.tasks,
    required this.activeTaskId,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    super.key,
  });

  final List<StudyTask> tasks;
  final String? activeTaskId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onDelete;

  @override
  State<TaskListCard> createState() => _TaskListCardState();
}

class _TaskListCardState extends State<TaskListCard> {
  final _controller = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAdd(text);
    _controller.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tasks', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final task in widget.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: widget.activeTaskId == task.id
                      ? task.color.withOpacity(0.18)
                      : Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => widget.onSelect(task.id),
                    leading: CircleAvatar(
                      radius: 8,
                      backgroundColor: task.color,
                    ),
                    title: Text(task.name),
                    trailing: IconButton(
                      tooltip: 'Delete task',
                      onPressed: () => widget.onDelete(task.id),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ),
              ),
            if (_adding)
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New task',
                  suffixIcon: IconButton(
                    onPressed: _submit,
                    icon: const Icon(Icons.check),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              )
            else
              OutlinedButton.icon(
                onPressed: () => setState(() => _adding = true),
                icon: const Icon(Icons.add),
                label: const Text('Add Task'),
              ),
          ],
        ),
      ),
    );
  }
}

class TimerCard extends StatelessWidget {
  const TimerCard({
    required this.task,
    required this.timer,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onFocus,
    super.key,
  });

  final StudyTask? task;
  final StudyTimerState timer;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onFocus;

  @override
  Widget build(BuildContext context) {
    final color = task?.color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.16), Colors.transparent],
          ),
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                tooltip: 'Focus mode',
                onPressed: onFocus,
                icon: const Icon(Icons.fullscreen),
              ),
            ),
            if (task != null)
              Chip(
                avatar: CircleAvatar(backgroundColor: task!.color),
                label: Text(task!.name),
              ),
            const SizedBox(height: 12),
            Text(
              formatClock(timer.elapsedSeconds),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              timer.isRunning
                  ? (timer.isPaused ? 'Paused' : 'Studying')
                  : 'Ready',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (!timer.isRunning)
                  FilledButton.icon(
                    onPressed: task == null ? null : onStart,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  )
                else if (timer.isPaused)
                  FilledButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  )
                else
                  FilledButton.icon(
                    onPressed: onPause,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (timer.isRunning)
                  FilledButton.tonalIcon(
                    onPressed: onStop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FocusTimerScreen extends StatelessWidget {
  const FocusTimerScreen({
    required this.task,
    required this.timer,
    required this.onExit,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    super.key,
  });

  final StudyTask? task;
  final StudyTimerState timer;
  final VoidCallback onExit;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final color = task?.color ?? const Color(0xFF9B87D6);
    return Scaffold(
      backgroundColor: const Color(0xFF09080D),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: GlowPainter(color))),
          Positioned(
            top: 18,
            right: 18,
            child: SafeArea(
              child: FilledButton.tonalIcon(
                onPressed: onExit,
                icon: const Icon(Icons.close),
                label: const Text('Exit'),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (task != null)
                    Chip(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      avatar: CircleAvatar(backgroundColor: task!.color),
                      label: Text(
                        task!.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  const SizedBox(height: 18),
                  FittedBox(
                    child: Text(
                      formatClock(timer.elapsedSeconds),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 120,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    timer.isRunning
                        ? (timer.isPaused ? 'Paused' : 'Focused')
                        : 'Ready',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (!timer.isRunning)
                        FilledButton.icon(
                          onPressed: task == null ? null : onStart,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Start'),
                        )
                      else if (timer.isPaused)
                        FilledButton.icon(
                          onPressed: onResume,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Resume'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: onPause,
                          icon: const Icon(Icons.pause),
                          label: const Text('Pause'),
                        ),
                      if (timer.isRunning)
                        FilledButton.tonalIcon(
                          onPressed: onStop,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop & Save'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CountdownCard extends StatelessWidget {
  const CountdownCard({
    required this.minutes,
    required this.secondsLeft,
    required this.isRunning,
    required this.onMinutesChanged,
    required this.onStart,
    required this.onStop,
    super.key,
  });

  final int minutes;
  final int secondsLeft;
  final bool isRunning;
  final ValueChanged<int> onMinutesChanged;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final progress = isRunning ? secondsLeft / (minutes * 60) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.timer_outlined),
                SizedBox(width: 8),
                Text('Countdown'),
              ],
            ),
            const SizedBox(height: 14),
            if (!isRunning) ...[
              TextFormField(
                initialValue: minutes.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
                onChanged: (value) =>
                    onMinutesChanged((int.tryParse(value) ?? 1).clamp(1, 120)),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
            ] else ...[
              Center(
                child: Text(
                  formatMinutes(secondsLeft),
                  style: Theme.of(
                    context,
                  ).textTheme.headlineLarge?.copyWith(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: onStop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StatsSection extends StatefulWidget {
  const StatsSection({required this.sessions, required this.tasks, super.key});

  final List<StudySession> sessions;
  final List<StudyTask> tasks;

  @override
  State<StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends State<StatsSection> {
  String _subjectRange = 'week';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = dateKey(now);
    final week = mondayWeek(now);
    final todaySeconds = widget.sessions
        .where((s) => s.date == today)
        .fold(0, (sum, s) => sum + s.duration);
    final weekSeconds = widget.sessions
        .where((s) => week.contains(s.date))
        .fold(0, (sum, s) => sum + s.duration);
    final pie = pieData(widget.sessions, widget.tasks, _subjectRange, now);
    final totalSubjectSeconds = pie.fold<int>(
      0,
      (sum, item) => sum + item.seconds,
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                icon: Icons.wb_sunny_outlined,
                title: 'Today',
                value: formatDuration(todaySeconds),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                icon: Icons.trending_up,
                title: 'This Week',
                value: formatDuration(weekSeconds),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time per Subject',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'today', label: Text('Today')),
                    ButtonSegment(value: 'week', label: Text('Week')),
                    ButtonSegment(value: 'month', label: Text('Month')),
                  ],
                  selected: {_subjectRange},
                  onSelectionChanged: (value) =>
                      setState(() => _subjectRange = value.first),
                ),
                const SizedBox(height: 14),
                if (pie.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('No sessions recorded yet.')),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 640;
                      final chart = SizedBox(
                        width: compact ? 180 : 220,
                        height: compact ? 180 : 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              data: pie,
                              holeColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Total',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                Text(
                                  formatDuration(totalSubjectSeconds),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      final details = Column(
                        children: [
                          for (final item in pie)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: SubjectTimeRow(item: item),
                            ),
                        ],
                      );
                      if (compact) {
                        return Column(
                          children: [
                            chart,
                            const SizedBox(height: 18),
                            details,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          chart,
                          const SizedBox(width: 28),
                          Expanded(child: details),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SubjectTimeRow extends StatelessWidget {
  const SubjectTimeRow({required this.item, super.key});

  final PiePoint item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(radius: 6, backgroundColor: item.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.name,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(formatDuration(item.seconds), style: textTheme.bodyMedium),
            const SizedBox(width: 10),
            SizedBox(
              width: 42,
              child: Text(
                '${item.percent}%',
                textAlign: TextAlign.end,
                style: textTheme.labelMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: item.percent / 100,
            minHeight: 8,
            backgroundColor: item.color.withOpacity(0.16),
            valueColor: AlwaysStoppedAnimation<Color>(item.color),
          ),
        ),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(title),
            const SizedBox(height: 8),
            FittedBox(
              child: Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BarChart extends StatelessWidget {
  const BarChart({required this.data, super.key});

  final List<ChartPoint> data;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: BarChartPainter(data, Theme.of(context).colorScheme.primary),
      child: const SizedBox.expand(),
    );
  }
}

class PieChart extends StatelessWidget {
  const PieChart({required this.data, required this.holeColor, super.key});

  final List<PiePoint> data;
  final Color holeColor;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: PieChartPainter(data, holeColor));
}

class GlowPainter extends CustomPainter {
  GlowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader =
          RadialGradient(
            colors: [color.withOpacity(0.5), Colors.transparent],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width / 2, size.height * 0.4),
              radius: size.shortestSide * 0.65,
            ),
          );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant GlowPainter oldDelegate) =>
      oldDelegate.color != color;
}

class BarChartPainter extends CustomPainter {
  BarChartPainter(this.data, this.color);
  final List<ChartPoint> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = Colors.grey.withOpacity(0.35)
      ..strokeWidth = 1;
    final bar = Paint()..color = color;
    final text = TextPainter(textDirection: TextDirection.ltr);
    final maxValue = math.max(
      1,
      data.fold<int>(0, (max, point) => math.max(max, point.minutes)),
    );
    final graph = Rect.fromLTWH(28, 8, size.width - 36, size.height - 40);
    canvas.drawLine(
      Offset(graph.left, graph.bottom),
      Offset(graph.right, graph.bottom),
      axis,
    );
    final width = graph.width / math.max(1, data.length);
    for (var i = 0; i < data.length; i += 1) {
      final point = data[i];
      final height = graph.height * (point.minutes / maxValue);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          graph.left + i * width + width * 0.18,
          graph.bottom - height,
          width * 0.64,
          height,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(rect, bar);
      if (data.length <= 12 || i % 4 == 0) {
        text.text = TextSpan(
          text: point.label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        );
        text.layout(maxWidth: width);
        text.paint(canvas, Offset(graph.left + i * width, graph.bottom + 8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant BarChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}

class PieChartPainter extends CustomPainter {
  PieChartPainter(this.data, this.holeColor);
  final List<PiePoint> data;
  final Color holeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = data.fold<int>(0, (sum, item) => sum + item.seconds);
    if (total <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.shortestSide / 2,
    );
    var start = -math.pi / 2;
    for (final item in data) {
      final sweep = (item.seconds / total) * math.pi * 2;
      canvas.drawArc(rect, start, sweep, true, Paint()..color = item.color);
      start += sweep;
    }
    canvas.drawCircle(
      rect.center,
      size.shortestSide * 0.24,
      Paint()..color = holeColor,
    );
  }

  @override
  bool shouldRepaint(covariant PieChartPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.holeColor != holeColor;
}

class StudyRepository {
  final FirebaseSyncClient _firebase = FirebaseSyncClient();
  static const _currentAuthKey = 'current_auth';

  String _userStateKey(String uid) => 'state_$uid';

  Future<AppState> load() async {
    try {
      final authJson = await readStoredValue(_currentAuthKey);
      if (authJson == null || authJson.isEmpty) return AppState.initial();
      final auth = AuthSession.fromJson(
        jsonDecode(authJson) as Map<String, dynamic>,
      );
      final stored = await readStoredValue(_userStateKey(auth.uid));
      if (stored == null || stored.isEmpty) {
        final empty = AppState.initial().copyWith(
          auth: auth,
          userName: auth.email.split('@').first,
          hasPendingSync: false,
        );
        return sync(empty, preferRemote: true);
      }
      final cached = AppState.fromJson(
        jsonDecode(stored) as Map<String, dynamic>,
      ).copyWith(auth: auth);
      return sync(cached, preferRemote: true);
    } catch (_) {
      return AppState.initial();
    }
  }

  Future<void> save(AppState state) async {
    final auth = state.auth;
    if (auth == null) return;
    await writeStoredValue(_currentAuthKey, jsonEncode(auth.toJson()));
    await writeStoredValue(_userStateKey(auth.uid), jsonEncode(state.toJson()));
  }

  Future<AuthResult> authenticate(
    String name,
    String email,
    String password,
    bool signUp,
  ) {
    return _firebase.authenticate(name, email, password, signUp);
  }

  Future<AppState> loadForAuth(AuthResult result) async {
    await writeStoredValue(_currentAuthKey, jsonEncode(result.auth.toJson()));
    try {
      final empty = AppState.initial().copyWith(
        auth: result.auth,
        userName: result.userName,
        hasPendingSync: false,
      );
      return sync(empty, preferRemote: true);
    } catch (error) {
      await deleteStoredValue(_currentAuthKey);
      throw Exception(_cleanSyncError(error));
    }
  }

  Future<void> logout() async {
    await deleteStoredValue(_currentAuthKey);
  }

  Future<AppState> sync(AppState state, {bool preferRemote = false}) async {
    try {
      final refreshedAuth = await _firebase.refreshIfNeeded(state.auth!);
      final authenticatedState = state.copyWith(auth: refreshedAuth);
      final remote = await _firebase.fetchState(refreshedAuth);
      final shouldUseRemote =
          preferRemote && !authenticatedState.hasPendingSync && remote != null;
      final merged = shouldUseRemote
          ? remote.copyWith(auth: refreshedAuth)
          : remote == null
          ? authenticatedState
          : authenticatedState.merge(remote);
      await _firebase.pushState(merged);
      await save(merged.copyWith(hasPendingSync: false));
      return merged.copyWith(hasPendingSync: false);
    } catch (error) {
      final pending = state.copyWith(hasPendingSync: true);
      await save(pending);
      throw Exception(_cleanSyncError(error));
    }
  }

  String _cleanSyncError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    return message.length <= 220 ? message : '${message.substring(0, 220)}...';
  }
}

class FirebaseSyncClient {
  bool get configured =>
      _firebaseProjectId.isNotEmpty && _firebaseApiKey.isNotEmpty;

  Future<AuthResult> authenticate(
    String name,
    String email,
    String password,
    bool signUp,
  ) async {
    if (!configured) {
      throw Exception(
        'Add FIREBASE_PROJECT_ID and FIREBASE_WEB_API_KEY with --dart-define to enable Firebase sync.',
      );
    }
    final url = Uri.https(
      'identitytoolkit.googleapis.com',
      signUp ? '/v1/accounts:signUp' : '/v1/accounts:signInWithPassword',
      {'key': _firebaseApiKey},
    );
    final response = await http.post(
      url,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(
        (body['error'] as Map<String, dynamic>?)?['message'] ??
            'Firebase auth failed',
      );
    }
    return AuthResult(
      auth: AuthSession(
        uid: body['localId'] as String,
        email: email,
        idToken: body['idToken'] as String,
        refreshToken: body['refreshToken'] as String,
        expiresAt: DateTime.now().add(
          Duration(
            seconds: int.tryParse(body['expiresIn'] as String? ?? '') ?? 3600,
          ),
        ),
      ),
      userName: signUp && name.isNotEmpty ? name : email.split('@').first,
    );
  }

  Future<AuthSession> refreshIfNeeded(AuthSession auth) async {
    if (!configured ||
        auth.expiresAt.isAfter(
          DateTime.now().add(const Duration(minutes: 5)),
        )) {
      return auth;
    }
    final url = Uri.https('securetoken.googleapis.com', '/v1/token', {
      'key': _firebaseApiKey,
    });
    final response = await http.post(
      url,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {'grant_type': 'refresh_token', 'refresh_token': auth.refreshToken},
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw Exception(
        'Token refresh failed (${response.statusCode}): ${response.body}',
      );
    }
    return AuthSession(
      uid: body['user_id'] as String,
      email: auth.email,
      idToken: body['id_token'] as String,
      refreshToken: body['refresh_token'] as String,
      expiresAt: DateTime.now().add(
        Duration(
          seconds: int.tryParse(body['expires_in'] as String? ?? '') ?? 3600,
        ),
      ),
    );
  }

  Future<AppState?> fetchState(AuthSession auth) async {
    if (!configured) return null;
    final url = Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$_firebaseProjectId/databases/(default)/documents/users/${auth.uid}/studyState/current',
    );
    final response = await http.get(
      url,
      headers: {'authorization': 'Bearer ${auth.idToken}'},
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 400) {
      throw Exception(
        'Firestore fetch failed (${response.statusCode}): ${response.body}',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final payload =
        (((body['fields'] as Map<String, dynamic>)['payload']
                as Map<String, dynamic>)['stringValue']
            as String?) ??
        '{}';
    return AppState.fromJson(
      jsonDecode(payload) as Map<String, dynamic>,
    ).copyWith(auth: auth);
  }

  Future<void> pushState(AppState state) async {
    if (!configured || state.auth == null) return;
    final url = Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/$_firebaseProjectId/databases/(default)/documents/users/${state.auth!.uid}/studyState/current',
    );
    final response = await http.patch(
      url,
      headers: {
        'authorization': 'Bearer ${state.auth!.idToken}',
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'fields': {
          'payload': {'stringValue': jsonEncode(state.toJson())},
          'updatedAt': {
            'timestampValue': state.updatedAt.toUtc().toIso8601String(),
          },
        },
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception(
        'Firestore push failed (${response.statusCode}): ${response.body}',
      );
    }
  }
}

class AuthResult {
  AuthResult({required this.auth, required this.userName});
  final AuthSession auth;
  final String userName;
}

class AppState {
  AppState({
    required this.tasks,
    required this.sessions,
    required this.timer,
    required this.countdown,
    required this.updatedAt,
    required this.userName,
    required this.isDark,
    this.activeTaskId,
    this.auth,
    this.hasPendingSync = false,
  });

  final List<StudyTask> tasks;
  final List<StudySession> sessions;
  final StudyTimerState timer;
  final CountdownState countdown;
  final String? activeTaskId;
  final DateTime updatedAt;
  final AuthSession? auth;
  final String userName;
  final bool isDark;
  final bool hasPendingSync;

  factory AppState.initial() {
    final now = DateTime.now();
    final tasks = [
      StudyTask(id: '1', name: 'Bio', colorHex: '#9b87d6', updatedAt: now),
      StudyTask(id: '2', name: 'Physics', colorHex: '#a8d5ff', updatedAt: now),
      StudyTask(id: '3', name: 'Chem', colorHex: '#ffb3c6', updatedAt: now),
    ];
    return AppState(
      tasks: tasks,
      sessions: const [],
      timer: StudyTimerState.empty(),
      countdown: CountdownState.initial(now),
      activeTaskId: '1',
      updatedAt: now,
      userName: 'Suu',
      isDark: false,
    );
  }

  AppState copyWith({
    List<StudyTask>? tasks,
    List<StudySession>? sessions,
    StudyTimerState? timer,
    CountdownState? countdown,
    String? activeTaskId,
    DateTime? updatedAt,
    AuthSession? auth,
    bool clearAuth = false,
    String? userName,
    bool? isDark,
    bool? hasPendingSync,
  }) {
    return AppState(
      tasks: tasks ?? this.tasks,
      sessions: sessions ?? this.sessions,
      timer: timer ?? this.timer,
      countdown: countdown ?? this.countdown,
      activeTaskId: activeTaskId ?? this.activeTaskId,
      updatedAt: updatedAt ?? this.updatedAt,
      auth: clearAuth ? null : auth ?? this.auth,
      userName: userName ?? this.userName,
      isDark: isDark ?? this.isDark,
      hasPendingSync: hasPendingSync ?? this.hasPendingSync,
    );
  }

  AppState touch() =>
      copyWith(updatedAt: DateTime.now(), hasPendingSync: true, auth: auth);

  AppState withRecomputedTimer() => copyWith(
    timer: timer.recompute(),
    countdown: countdown.recompute(),
    auth: auth,
  );

  AppState addSession(String taskId, int duration) {
    final now = DateTime.now();
    final start = now.subtract(Duration(seconds: duration));
    return addSessionRange(taskId, start, now);
  }

  AppState addSessionFromTimer(String taskId, StudyTimerState timer) {
    if (!timer.isRunning || timer.isPaused || timer.startTime == null)
      return this;
    final end = DateTime.now();
    if (!end.isAfter(timer.startTime!)) return this;
    return addSessionRange(taskId, timer.startTime!, end);
  }

  AppState addSessionRange(String taskId, DateTime start, DateTime end) {
    if (!end.isAfter(start)) return this;
    final now = DateTime.now();
    final splitSessions = <StudySession>[];
    var cursor = start;
    var index = 0;

    while (cursor.isBefore(end)) {
      final nextHour = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        cursor.hour + 1,
      );
      final segmentEnd = nextHour.isBefore(end) ? nextHour : end;
      final duration = segmentEnd.difference(cursor).inSeconds;
      if (duration > 0) {
        splitSessions.add(
          StudySession(
            id: '${now.microsecondsSinceEpoch}-$index',
            taskId: taskId,
            duration: duration,
            date: dateKey(cursor),
            hour: cursor.hour,
            createdAt: cursor,
            updatedAt: now,
          ),
        );
        index += 1;
      }
      cursor = segmentEnd;
    }

    return copyWith(sessions: [...sessions, ...splitSessions], auth: auth);
  }

  AppState merge(AppState remote) {
    final taskMap = {for (final task in tasks) task.id: task};
    for (final task in remote.tasks) {
      final local = taskMap[task.id];
      if (local == null || task.updatedAt.isAfter(local.updatedAt))
        taskMap[task.id] = task;
    }
    final sessionMap = {for (final session in sessions) session.id: session};
    for (final session in remote.sessions) {
      final local = sessionMap[session.id];
      if (local == null || session.updatedAt.isAfter(local.updatedAt))
        sessionMap[session.id] = session;
    }
    final chosenTimer = remote.timer.updatedAt.isAfter(timer.updatedAt)
        ? remote.timer
        : timer;
    final chosenCountdown =
        remote.countdown.updatedAt.isAfter(countdown.updatedAt)
        ? remote.countdown
        : countdown;
    return copyWith(
      tasks: taskMap.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
      sessions: sessionMap.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      timer: chosenTimer,
      countdown: chosenCountdown,
      activeTaskId: remote.updatedAt.isAfter(updatedAt)
          ? remote.activeTaskId
          : activeTaskId,
      updatedAt: remote.updatedAt.isAfter(updatedAt)
          ? remote.updatedAt
          : updatedAt,
      auth: auth,
      userName: remote.updatedAt.isAfter(updatedAt)
          ? remote.userName
          : userName,
      isDark: remote.updatedAt.isAfter(updatedAt) ? remote.isDark : isDark,
    );
  }

  Map<String, dynamic> toJson() => {
    'tasks': tasks.map((task) => task.toJson()).toList(),
    'sessions': sessions.map((session) => session.toJson()).toList(),
    'timer': timer.toJson(),
    'countdown': countdown.toJson(),
    'activeTaskId': activeTaskId,
    'updatedAt': updatedAt.toIso8601String(),
    'auth': auth?.toJson(),
    'userName': userName,
    'isDark': isDark,
    'hasPendingSync': hasPendingSync,
  };

  factory AppState.fromJson(Map<String, dynamic> json) => AppState(
    tasks: (json['tasks'] as List<dynamic>? ?? [])
        .map((item) => StudyTask.fromJson(item as Map<String, dynamic>))
        .toList(),
    sessions: (json['sessions'] as List<dynamic>? ?? [])
        .map((item) => StudySession.fromJson(item as Map<String, dynamic>))
        .toList(),
    timer: StudyTimerState.fromJson(
      json['timer'] as Map<String, dynamic>? ?? const {},
    ),
    countdown: CountdownState.fromJson(
      json['countdown'] as Map<String, dynamic>? ?? const {},
    ),
    activeTaskId: json['activeTaskId'] as String?,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    auth: json['auth'] == null
        ? null
        : AuthSession.fromJson(json['auth'] as Map<String, dynamic>),
    userName: json['userName'] as String? ?? 'Suu',
    isDark: json['isDark'] as bool? ?? false,
    hasPendingSync: json['hasPendingSync'] as bool? ?? false,
  );
}

class AuthSession {
  AuthSession({
    required this.uid,
    required this.email,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });
  final String uid;
  final String email;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'email': email,
    'idToken': idToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    uid: json['uid'] as String,
    email: json['email'] as String,
    idToken: json['idToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt:
        DateTime.tryParse(json['expiresAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class StudyTask {
  StudyTask({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.updatedAt,
  });
  final String id;
  final String name;
  final String colorHex;
  final DateTime updatedAt;

  Color get color => colorFromHex(colorHex);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorHex,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StudyTask.fromJson(Map<String, dynamic> json) => StudyTask(
    id: json['id'] as String,
    name: json['name'] as String,
    colorHex: json['color'] as String? ?? '#9b87d6',
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class StudySession {
  StudySession({
    required this.id,
    required this.taskId,
    required this.duration,
    required this.date,
    required this.hour,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String taskId;
  final int duration;
  final String date;
  final int hour;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'duration': duration,
    'date': date,
    'hour': hour,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StudySession.fromJson(Map<String, dynamic> json) => StudySession(
    id:
        json['id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    taskId: json['taskId'] as String,
    duration: (json['duration'] as num).toInt(),
    date: json['date'] as String,
    hour: (json['hour'] as num?)?.toInt() ?? 0,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class CountdownState {
  CountdownState({
    required this.minutes,
    required this.endsAt,
    required this.updatedAt,
  });

  final int minutes;
  final DateTime? endsAt;
  final DateTime updatedAt;

  bool get isRunning => secondsLeft > 0;

  int get secondsLeft {
    final end = endsAt;
    if (end == null) return 0;
    return math.max(0, end.difference(DateTime.now()).inSeconds);
  }

  factory CountdownState.initial(DateTime now) =>
      CountdownState(minutes: 25, endsAt: null, updatedAt: now);

  CountdownState copyWith({
    int? minutes,
    DateTime? endsAt,
    bool clearEndsAt = false,
    DateTime? updatedAt,
  }) {
    return CountdownState(
      minutes: minutes ?? this.minutes,
      endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  CountdownState start() {
    final now = DateTime.now();
    return copyWith(
      endsAt: now.add(Duration(minutes: minutes.clamp(1, 120))),
      updatedAt: now,
    );
  }

  CountdownState stop() =>
      copyWith(clearEndsAt: true, updatedAt: DateTime.now());

  CountdownState recompute() {
    if (endsAt == null || secondsLeft > 0) return this;
    return stop();
  }

  Map<String, dynamic> toJson() => {
    'minutes': minutes,
    'endsAt': endsAt?.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory CountdownState.fromJson(Map<String, dynamic> json) => CountdownState(
    minutes: ((json['minutes'] as num?)?.toInt() ?? 25).clamp(1, 120),
    endsAt: DateTime.tryParse(json['endsAt'] as String? ?? ''),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  ).recompute();
}

class StudyTimerState {
  StudyTimerState({
    required this.isRunning,
    required this.isPaused,
    required this.startedAt,
    required this.startTime,
    required this.elapsedBeforePause,
    required this.elapsedSeconds,
    required this.updatedAt,
  });

  final bool isRunning;
  final bool isPaused;
  final DateTime? startedAt;
  final DateTime? startTime;
  final int elapsedBeforePause;
  final int elapsedSeconds;
  final DateTime updatedAt;

  factory StudyTimerState.empty() => StudyTimerState(
    isRunning: false,
    isPaused: false,
    startedAt: null,
    startTime: null,
    elapsedBeforePause: 0,
    elapsedSeconds: 0,
    updatedAt: DateTime.now(),
  );

  StudyTimerState copyWith({
    bool? isRunning,
    bool? isPaused,
    DateTime? startedAt,
    DateTime? startTime,
    int? elapsedBeforePause,
    int? elapsedSeconds,
    DateTime? updatedAt,
  }) {
    return StudyTimerState(
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      startedAt: startedAt ?? this.startedAt,
      startTime: startTime,
      elapsedBeforePause: elapsedBeforePause ?? this.elapsedBeforePause,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  StudyTimerState recompute() {
    if (!isRunning || isPaused || startTime == null) return this;
    final elapsed =
        elapsedBeforePause + DateTime.now().difference(startTime!).inSeconds;
    return copyWith(elapsedSeconds: math.max(0, elapsed), startTime: startTime);
  }

  Map<String, dynamic> toJson() => {
    'isRunning': isRunning,
    'isPaused': isPaused,
    'startedAt': startedAt?.toIso8601String(),
    'startTime': startTime?.toIso8601String(),
    'elapsedBeforePause': elapsedBeforePause,
    'elapsedSeconds': elapsedSeconds,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StudyTimerState.fromJson(Map<String, dynamic> json) =>
      StudyTimerState(
        isRunning: json['isRunning'] as bool? ?? false,
        isPaused: json['isPaused'] as bool? ?? false,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
        startTime: DateTime.tryParse(json['startTime'] as String? ?? ''),
        elapsedBeforePause: (json['elapsedBeforePause'] as num?)?.toInt() ?? 0,
        elapsedSeconds: (json['elapsedSeconds'] as num?)?.toInt() ?? 0,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      ).recompute();
}

class ChartPoint {
  ChartPoint(this.label, this.minutes);
  final String label;
  final int minutes;
}

class PiePoint {
  PiePoint(this.name, this.seconds, this.color, this.percent);
  final String name;
  final int seconds;
  final Color color;
  final int percent;
}

List<ChartPoint> chartData(
  List<StudySession> sessions,
  String range,
  DateTime now,
) {
  if (range == 'daily') {
    return List.generate(24, (hour) {
      final total = sessions
          .where((s) => s.date == dateKey(now) && s.hour == hour)
          .fold(0, (sum, s) => sum + s.duration);
      return ChartPoint('$hour', (total / 60).round());
    });
  }
  if (range == 'monthly') {
    return List.generate(30, (index) {
      final date = now.subtract(Duration(days: 29 - index));
      final key = dateKey(date);
      final total = sessions
          .where((s) => s.date == key)
          .fold(0, (sum, s) => sum + s.duration);
      return ChartPoint('${date.day}', (total / 60).round());
    });
  }
  final week = mondayWeek(now);
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return List.generate(7, (index) {
    final total = sessions
        .where((s) => s.date == week[index])
        .fold(0, (sum, s) => sum + s.duration);
    return ChartPoint(labels[index], (total / 60).round());
  });
}

List<PiePoint> pieData(
  List<StudySession> sessions,
  List<StudyTask> tasks,
  String range,
  DateTime now,
) {
  final week = mondayWeek(now);
  final monthPrefix =
      '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-';
  final filtered = sessions.where((session) {
    if (range == 'today') return session.date == dateKey(now);
    if (range == 'week') return week.contains(session.date);
    if (range == 'month') return session.date.startsWith(monthPrefix);
    return false;
  }).toList();
  final totals = <String, int>{};
  for (final session in filtered) {
    totals[session.taskId] = (totals[session.taskId] ?? 0) + session.duration;
  }
  final allSeconds = totals.values.fold(0, (sum, value) => sum + value);
  return tasks
      .where((task) => (totals[task.id] ?? 0) > 0)
      .map(
        (task) => PiePoint(
          task.name,
          totals[task.id]!,
          task.color,
          allSeconds == 0 ? 0 : ((totals[task.id]! / allSeconds) * 100).round(),
        ),
      )
      .toList()
    ..sort((a, b) => b.seconds.compareTo(a.seconds));
}

List<String> mondayWeek(DateTime now) {
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  return List.generate(
    7,
    (index) => dateKey(monday.add(Duration(days: index))),
  );
}

String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String formatClock(int seconds) {
  final hrs = seconds ~/ 3600;
  final mins = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

String formatMinutes(int seconds) {
  final mins = seconds ~/ 60;
  final secs = seconds % 60;
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

String formatDuration(int seconds) {
  final hrs = seconds ~/ 3600;
  final mins = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (hrs > 0) return '${hrs}h ${mins}m ${secs}s';
  if (mins > 0) return '${mins}m ${secs}s';
  return '${secs}s';
}

Color colorFromHex(String hex) {
  final clean = hex.replaceFirst('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}
