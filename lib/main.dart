import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const PomodoroApp());
}

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pomodoro Timer',
      theme: ThemeData.dark(),
      home: const PomodoroScreen(),
    );
  }
}

class PomodoroScreen extends StatefulWidget {
  const PomodoroScreen({super.key});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> with WidgetsBindingObserver {
  // Mode selection: false = 25+5 min mode, true = 50+10 min mode
  bool _is50MinMode = false;

  int get workTimeSeconds => (_is50MinMode ? 50 : 25) * 60;
  int get breakTimeSeconds => (_is50MinMode ? 10 : 5) * 60;

  late int _timeLeft;
  bool _isRunning = false;
  bool _isWorkTime = true;
  Timer? _timer;
  
  // Track system clock for background accuracy
  DateTime? _targetEndTime;

  // Session counter variable
  int _completedSessions = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeLeft = workTimeSeconds;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Recalculate remaining time when returning from background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning && _targetEndTime != null) {
      _updateRemainingTime();
    }
  }

  void _updateRemainingTime() {
    if (_targetEndTime == null) return;
    
    final now = DateTime.now();
    final difference = _targetEndTime!.difference(now).inSeconds;

    setState(() {
      if (difference > 0) {
        _timeLeft = difference;
      } else {
        // Increment session count if work time finishes
        if (_isWorkTime) {
          _completedSessions++;
        }

        // Toggle work/break mode
        _isWorkTime = !_isWorkTime;
        _timeLeft = _isWorkTime ? workTimeSeconds : breakTimeSeconds;
        _targetEndTime = DateTime.now().add(Duration(seconds: _timeLeft));
      }
    });
  }

  void _toggleMode() {
    _timer?.cancel();
    setState(() {
      _is50MinMode = !_is50MinMode;
      _isRunning = false;
      _isWorkTime = true;
      _timeLeft = workTimeSeconds;
      _targetEndTime = null;
    });
  }

  void _startTimer() {
    if (_timer != null) _timer!.cancel();
    
    _targetEndTime = DateTime.now().add(Duration(seconds: _timeLeft));
    setState(() => _isRunning = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemainingTime();
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _targetEndTime = null;
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isWorkTime = true;
      _timeLeft = workTimeSeconds;
      _targetEndTime = null;
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomodoro Timer'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Mode Switcher Button
            GestureDetector(
              onTap: _toggleMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade800,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.blueAccent, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Text(
                      _is50MinMode ? 'Mode: 50+10 Min (Tap to switch)' : 'Mode: 25+5 Min (Tap to switch)',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),

            // Work / Break Status Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: _isWorkTime ? Colors.redAccent : Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _isWorkTime ? 'Work Time' : 'Break Time',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 25),

            // Main Timer Display
            GestureDetector(
              onTap: _toggleMode,
              child: Text(
                _formatTime(_timeLeft),
                style: const TextStyle(fontSize: 76, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '💡 Tap timer to switch 25m / 50m modes',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 30),

            // Session Counter Section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🍅 Completed Sessions: ',
                    style: TextStyle(fontSize: 15, color: Colors.white70),
                  ),
                  Text(
                    '$_completedSessions',
                    style: const TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.redAccent,
                    ),
                  ),
                  if (_completedSessions > 0) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => setState(() => _completedSessions = 0),
                      child: const Icon(Icons.refresh, size: 18, color: Colors.grey),
                    ),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 35),

            // Controls (Start / Pause / Reset)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 64,
                  icon: Icon(_isRunning ? Icons.pause_circle_filled : Icons.play_circle_fill),
                  color: Colors.blueAccent,
                  onPressed: _isRunning ? _pauseTimer : _startTimer,
                ),
                const SizedBox(width: 20),
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.replay),
                  color: Colors.grey,
                  onPressed: _resetTimer,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
