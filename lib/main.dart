import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  // Custom durations in minutes
  int _workMinutes = 25; // Default: 25 mins (Range: 1 to 60)
  int _breakMinutes = 5;  // Default: 5 mins  (Range: 1 to 15)

  int get workTimeSeconds => _workMinutes * 60;
  int get breakTimeSeconds => _breakMinutes * 60;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning && _targetEndTime != null) {
      _updateRemainingTime();
    }
  }

  // Play system sound pattern (Beep) when timer finishes
  Future<void> _playBeepSound() async {
    for (int i = 0; i < 4; i++) {
      SystemSound.play(SystemSoundType.click);
      await Future.delayed(const Duration(milliseconds: 150));
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
        // Play sound when timer reaches 00:00
        _playBeepSound();

        if (_isWorkTime) {
          _completedSessions++;
        }

        _isWorkTime = !_isWorkTime;
        _timeLeft = _isWorkTime ? workTimeSeconds : breakTimeSeconds;
        _targetEndTime = DateTime.now().add(Duration(seconds: _timeLeft));
      }
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

  // Dialog to set custom timer durations (Work: 1-60m, Break: 1-15m)
  void _showCustomTimeDialog() {
    int tempWork = _workMinutes;
    int tempBreak = _breakMinutes;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.blueAccent),
                  SizedBox(width: 10),
                  Text('Set Custom Timer'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Work Duration Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Work Time:'),
                      Text(
                        '$tempWork min',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                      ),
                    ],
                  ),
                  Slider(
                    value: tempWork.toDouble(),
                    min: 1,
                    max: 60,
                    divisions: 59,
                    activeColor: Colors.redAccent,
                    label: '$tempWork min',
                    onChanged: (value) {
                      setDialogState(() => tempWork = value.toInt());
                    },
                  ),
                  const SizedBox(height: 15),

                  // Break Duration Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Break Time:'),
                      Text(
                        '$tempBreak min',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  Slider(
                    value: tempBreak.toDouble(),
                    min: 1,
                    max: 15,
                    divisions: 14,
                    activeColor: Colors.green,
                    label: '$tempBreak min',
                    onChanged: (value) {
                      setDialogState(() => tempBreak = value.toInt());
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () {
                    _timer?.cancel();
                    setState(() {
                      _workMinutes = tempWork;
                      _breakMinutes = tempBreak;
                      _isRunning = false;
                      _isWorkTime = true;
                      _timeLeft = workTimeSeconds;
                      _targetEndTime = null;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Developer About Dialog
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.person, color: Colors.blueAccent),
              SizedBox(width: 10),
              Text('About Developer'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Created by joy',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),
              const Text(
                'A simple and efficient Pomodoro Timer designed to help boost your focus and productivity.',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 20),
              
              // Facebook Link Display Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.facebook, color: Color(0xFF1877F2), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Facebook Profile',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    SelectableText(
                      'https://www.facebook.com/IMALONEJOY',
                      style: TextStyle(fontSize: 12, color: Colors.blueAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomodoro Timer'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'custom_time') {
                _showCustomTimeDialog();
              } else if (value == 'about') {
                _showAboutDialog();
              }
            },
            itemBuilder: (context) {
              return [
                const PopupMenuItem<String>(
                  value: 'custom_time',
                  child: Row(
                    children: [
                      Icon(Icons.tune, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('Set Custom Time'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'about',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('About Developer'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Current Configured Mode Indicator
            GestureDetector(
              onTap: _showCustomTimeDialog,
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
                    const Icon(Icons.timer_outlined, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Text(
                      'Mode: $_workMinutes + $_breakMinutes Min (Tap to change)',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 25),

            // Work / Break Status Badge
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

            // Timer Clock Display
            GestureDetector(
              onTap: _showCustomTimeDialog,
              child: Text(
                _formatTime(_timeLeft),
                style: const TextStyle(fontSize: 76, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '💡 Tap timer to adjust custom minutes',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 30),

            // Session Counter
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
