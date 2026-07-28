import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PomodoroApp());
}

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pomodoro Timer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.blueAccent,
      ),
      home: const PomodoroHomeScreen(),
    );
  }
}

class SessionEntry {
  final DateTime dateTime;
  final int durationMinutes;

  SessionEntry({
    required this.dateTime,
    required this.durationMinutes,
  });

  Map<String, dynamic> toJson() => {
        'dateTime': dateTime.toIso8601String(),
        'durationMinutes': durationMinutes,
      };

  factory SessionEntry.fromJson(Map<String, dynamic> json) => SessionEntry(
        dateTime: DateTime.parse(json['dateTime']),
        durationMinutes: json['durationMinutes'],
      );
}

class PomodoroHomeScreen extends StatefulWidget {
  const PomodoroHomeScreen({super.key});

  @override
  State<PomodoroHomeScreen> createState() => _PomodoroHomeScreenState();
}

class _PomodoroHomeScreenState extends State<PomodoroHomeScreen>
    with WidgetsBindingObserver {
  int _workMinutes = 25;
  int _breakMinutes = 5;

  int get workTimeSeconds => _workMinutes * 60;
  int get breakTimeSeconds => _breakMinutes * 60;

  int _timeLeft = 25 * 60;
  Timer? _timer;
  bool _isRunning = false;
  bool _isWorkTime = true;

  bool _isOvertime = false;
  int _overtimeSeconds = 0;

  bool _isBreakOvertime = false;
  int _breakOvertimeSeconds = 0;

  DateTime? _targetEndTime;

  List<SessionEntry> _sessionLogs = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _currentOrientation = 'auto';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timeLeft = workTimeSeconds;
    _loadSessionLogs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _audioPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadSessionLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? logsString = prefs.getString('pomodoro_session_logs');
    if (logsString != null) {
      final List<dynamic> decoded = jsonDecode(logsString);
      setState(() {
        _sessionLogs = decoded.map((e) => SessionEntry.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveSessionLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded =
        jsonEncode(_sessionLogs.map((e) => e.toJson()).toList());
    await prefs.setString('pomodoro_session_logs', encoded);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning && _targetEndTime != null) {
      _updateRemainingTime();
    }
  }

  Uint8List _generateBeepWav() {
    const int sampleRate = 22050;
    const double frequency = 880.0;
    const int durationMs = 600;
    const int numSamples = (sampleRate * durationMs) ~/ 1000;
    const int dataSize = numSamples * 2;
    final int fileSize = 44 + dataSize;

    final ByteData bytes = ByteData(fileSize);

    bytes.setUint32(0, 0x52494646, Endian.big);
    bytes.setUint32(4, fileSize - 8, Endian.little);
    bytes.setUint32(8, 0x57415645, Endian.big);

    bytes.setUint32(12, 0x666d7420, Endian.big);
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);

    bytes.setUint32(36, 0x64617461, Endian.big);
    bytes.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      double t = i / sampleRate;
      double sample = math.sin(2 * math.pi * frequency * t);
      int pcm = (sample * 32767).toInt().clamp(-32768, 32767);
      bytes.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return bytes.buffer.asUint8List();
  }

  Future<void> _playBeepSound() async {
    try {
      final wavBytes = _generateBeepWav();
      await _audioPlayer.play(BytesSource(wavBytes));
    } catch (_) {
      SystemSound.play(SystemSoundType.alert);
    }

    try {
      HapticFeedback.vibrate();
    } catch (_) {}
  }

  void _updateRemainingTime() {
    if (_targetEndTime == null) return;

    final now = DateTime.now();

    setState(() {
      if (_isWorkTime) {
        if (!_isOvertime) {
          final difference = _targetEndTime!.difference(now).inSeconds;
          if (difference > 0) {
            _timeLeft = difference;
          } else {
            _timeLeft = 0;
            _isOvertime = true;
            _overtimeSeconds = 0;
            _playBeepSound();

            _sessionLogs.insert(
              0,
              SessionEntry(dateTime: DateTime.now(), durationMinutes: _workMinutes),
            );
            _saveSessionLogs();

            _targetEndTime = DateTime.now();
          }
        } else {
          _overtimeSeconds = now.difference(_targetEndTime!).inSeconds;
        }
      } else {
        if (!_isBreakOvertime) {
          final difference = _targetEndTime!.difference(now).inSeconds;
          if (difference > 0) {
            _timeLeft = difference;
          } else {
            _timeLeft = 0;
            _isBreakOvertime = true;
            _breakOvertimeSeconds = 0;
            _playBeepSound();

            _targetEndTime = DateTime.now();
          }
        } else {
          _breakOvertimeSeconds = now.difference(_targetEndTime!).inSeconds;
        }
      }
    });
  }

  void _startTimer() {
    if (_timer != null) _timer!.cancel();

    // Screen keeps ON while timer is running
    WakelockPlus.enable();

    final now = DateTime.now();
    if (_isWorkTime) {
      if (!_isOvertime) {
        _targetEndTime = now.add(Duration(seconds: _timeLeft));
      } else {
        _targetEndTime = now.subtract(Duration(seconds: _overtimeSeconds));
      }
    } else {
      if (!_isBreakOvertime) {
        _targetEndTime = now.add(Duration(seconds: _timeLeft));
      } else {
        _targetEndTime = now.subtract(Duration(seconds: _breakOvertimeSeconds));
      }
    }

    setState(() => _isRunning = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemainingTime();
    });
  }

  void _pauseTimer() {
    _timer?.cancel();

    // Disable screen wake lock when timer is paused
    WakelockPlus.disable();

    setState(() {
      _isRunning = false;
    });
  }

  void _resetTimer() {
    _timer?.cancel();

    // Disable screen wake lock when timer is reset
    WakelockPlus.disable();

    setState(() {
      _isRunning = false;
      _isWorkTime = true;
      _isOvertime = false;
      _overtimeSeconds = 0;
      _isBreakOvertime = false;
      _breakOvertimeSeconds = 0;
      _timeLeft = workTimeSeconds;
      _targetEndTime = null;
    });
  }

  void _startBreakTime() {
    _timer?.cancel();

    // Screen keeps ON during Break Time
    WakelockPlus.enable();

    if (_overtimeSeconds >= 60 && _sessionLogs.isNotEmpty) {
      int extraMinutes = _overtimeSeconds ~/ 60;
      
      setState(() {
        _sessionLogs[0] = SessionEntry(
          dateTime: _sessionLogs[0].dateTime,
          durationMinutes: _sessionLogs[0].durationMinutes + extraMinutes,
        );
      });
      _saveSessionLogs();
    }

    setState(() {
      _isWorkTime = false;
      _isOvertime = false;
      _overtimeSeconds = 0;
      _isBreakOvertime = false;
      _breakOvertimeSeconds = 0;
      _timeLeft = breakTimeSeconds;
      _targetEndTime = DateTime.now().add(Duration(seconds: _timeLeft));
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateRemainingTime();
    });
  }

  void _stopBreakTime() {
    _timer?.cancel();

    // Disable screen wake lock when break time stops
    WakelockPlus.disable();

    setState(() {
      _isWorkTime = true;
      _isOvertime = false;
      _overtimeSeconds = 0;
      _isBreakOvertime = false;
      _breakOvertimeSeconds = 0;
      _timeLeft = workTimeSeconds;
      _targetEndTime = null;
      _isRunning = false;
    });
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDateOnly(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _calculateTotalDuration(List<SessionEntry> entries) {
    int totalMinutes = entries.fold(0, (sum, item) => sum + item.durationMinutes);
    int hours = totalMinutes ~/ 60;
    int minutes = totalMinutes % 60;
    if (hours > 0) {
      return '$hours hrs $minutes mins';
    }
    return '$minutes mins';
  }

  String _getDisplayTimeText() {
    if (_isWorkTime) {
      if (!_isOvertime) {
        return _formatTime(_timeLeft);
      } else {
        return '+ ${_formatTime(_overtimeSeconds)}';
      }
    } else {
      if (!_isBreakOvertime) {
        return _formatTime(_timeLeft);
      } else {
        return '- ${_formatTime(_breakOvertimeSeconds)}';
      }
    }
  }

  Color _getDisplayTimeColor() {
    if (_isWorkTime) {
      if (_isOvertime) {
        return Colors.redAccent;
      }
      return Colors.white;
    } else {
      if (_isBreakOvertime) {
        return Colors.orangeAccent;
      }
      return Colors.greenAccent;
    }
  }

  void _changeOrientation(String mode) {
    setState(() {
      _currentOrientation = mode;
    });

    if (mode == 'portrait') {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } else if (mode == 'landscape') {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _showOrientationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.screen_rotation, color: Colors.blueAccent),
              SizedBox(width: 10),
              Text('Screen Mode'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.stay_current_portrait, color: Colors.blueAccent),
                title: const Text('Portrait Mode'),
                trailing: _currentOrientation == 'portrait'
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  _changeOrientation('portrait');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.stay_current_landscape, color: Colors.blueAccent),
                title: const Text('Landscape Mode'),
                trailing: _currentOrientation == 'landscape'
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  _changeOrientation('landscape');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.screen_rotation_outlined, color: Colors.blueAccent),
                title: const Text('Auto Rotate'),
                trailing: _currentOrientation == 'auto'
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
                onTap: () {
                  _changeOrientation('auto');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                      _isOvertime = false;
                      _overtimeSeconds = 0;
                      _isBreakOvertime = false;
                      _breakOvertimeSeconds = 0;
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
                'Developed by LKJOY',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),
              const Text(
                'A simple and efficient Pomodoro Timer designed to help boost your focus and productivity.',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 20),
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
  }  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomodoro Timer', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.screen_rotation, color: Colors.blueAccent),
            onPressed: _showOrientationDialog,
            tooltip: 'Screen Mode',
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.blueAccent),
            onPressed: _showCustomTimeDialog,
            tooltip: 'Custom Timer',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.blueAccent),
            onPressed: _showAboutDialog,
            tooltip: 'About Developer',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isWorkTime
                            ? (_isOvertime ? Colors.redAccent.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2))
                            : (_isBreakOvertime ? Colors.orangeAccent.withOpacity(0.2) : Colors.greenAccent.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _isWorkTime
                            ? (_isOvertime ? 'WORK OVERTIME' : 'WORK TIME')
                            : (_isBreakOvertime ? 'BREAK OVERTIME' : 'BREAK TIME'),
                        style: TextStyle(
                          color: _isWorkTime
                              ? (_isOvertime ? Colors.redAccent : Colors.blueAccent)
                              : (_isBreakOvertime ? Colors.orangeAccent : Colors.greenAccent),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _getDisplayTimeText(),
                        style: TextStyle(
                          fontSize: 68,
                          fontWeight: FontWeight.bold,
                          color: _getDisplayTimeColor(),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_isRunning)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _startTimer,
                            icon: const Icon(Icons.play_arrow, color: Colors.white),
                            label: const Text('Start', style: TextStyle(color: Colors.white, fontSize: 16)),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _pauseTimer,
                            icon: const Icon(Icons.pause, color: Colors.white),
                            label: const Text('Pause', style: TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                        const SizedBox(width: 12),
                        if (_isWorkTime)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _startBreakTime,
                            icon: const Icon(Icons.coffee, color: Colors.white),
                            label: const Text('Start Break', style: TextStyle(color: Colors.white, fontSize: 15)),
                          )
                        else
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purpleAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _stopBreakTime,
                            icon: const Icon(Icons.work, color: Colors.white),
                            label: const Text('Work Mode', style: TextStyle(color: Colors.white, fontSize: 15)),
                          ),
                        const SizedBox(width: 12),
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white10,
                            padding: const EdgeInsets.all(12),
                          ),
                          onPressed: _resetTimer,
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          tooltip: 'Reset Timer',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 25),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bar_chart, color: Colors.blueAccent),
                            SizedBox(width: 8),
                            Text(
                              'Focus Statistics',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Text(
                          'Total: ${_calculateTotalDuration(_sessionLogs)}',
                          style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Divider(height: 25, color: Colors.white10),
                    _sessionLogs.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'No completed sessions yet.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _sessionLogs.length > 10 ? 10 : _sessionLogs.length,
                            separatorBuilder: (context, index) => const Divider(color: Colors.white12),
                            itemBuilder: (context, index) {
                              final entry = _sessionLogs[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.white10,
                                  child: Icon(Icons.check, size: 16, color: Colors.greenAccent),
                                ),
                                title: Text(
                                  '${entry.durationMinutes} Minutes Focused',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                subtitle: Text(
                                  _formatDateTime(entry.dateTime),
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                                trailing: Text(
                                  _formatDateOnly(entry.dateTime),
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

