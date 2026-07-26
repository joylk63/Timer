import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PomodoroApp());
}

// Session Model Class for JSON Serialization
class SessionEntry {
  final DateTime dateTime;
  final int durationMinutes;

  SessionEntry({required this.dateTime, required this.durationMinutes});

  Map<String, dynamic> toJson() => {
        'dateTime': dateTime.toIso8601String(),
        'durationMinutes': durationMinutes,
      };

  factory SessionEntry.fromJson(Map<String, dynamic> json) => SessionEntry(
        dateTime: DateTime.parse(json['dateTime']),
        durationMinutes: json['durationMinutes'],
      );
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
  int _workMinutes = 25;
  int _breakMinutes = 5;

  int get workTimeSeconds => _workMinutes * 60;
  int get breakTimeSeconds => _breakMinutes * 60;

  late int _timeLeft;
  bool _isRunning = false;
  bool _isWorkTime = true;
  Timer? _timer;

  // Track system clock for background accuracy
  DateTime? _targetEndTime;

  // List to store completed session logs
  List<SessionEntry> _sessionLogs = [];

  // Selected date in calendar view
  DateTime _selectedCalendarDate = DateTime.now();

  // Current orientation mode tracker
  String _currentOrientation = 'auto'; // 'portrait', 'landscape', 'auto'

  // Audio player instance
  final AudioPlayer _audioPlayer = AudioPlayer();

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
    super.dispose();
  }

  // Calculate "Work Date" considering 4:00 AM as the reset boundary
  DateTime _getWorkDate(DateTime dt) {
    if (dt.hour < 4) {
      DateTime yesterday = dt.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    } else {
      return DateTime(dt.year, dt.month, dt.day);
    }
  }

  bool _isSameWorkDate(DateTime dt1, DateTime dt2) {
    DateTime w1 = _getWorkDate(dt1);
    DateTime w2 = _getWorkDate(dt2);
    return w1.year == w2.year && w1.month == w2.month && w1.day == w2.day;
  }

  // Compare log's work date directly with the calendar selected date
  bool _isLogOnCalendarDate(DateTime logDt, DateTime calendarDt) {
    DateTime workDate = _getWorkDate(logDt);
    return workDate.year == calendarDt.year &&
        workDate.month == calendarDt.month &&
        workDate.day == calendarDt.day;
  }

  // Count sessions completed for "Today" (since 4:00 AM today)
  int get _todaySessionsCount {
    DateTime now = DateTime.now();
    return _sessionLogs.where((log) => _isSameWorkDate(log.dateTime, now)).length;
  }

  // Load saved session logs from Local Storage
  Future<void> _loadSessionLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? rawLogs = prefs.getStringList('pomodoro_logs');
    if (rawLogs != null) {
      setState(() {
        _sessionLogs = rawLogs.map((item) => SessionEntry.fromJson(jsonDecode(item))).toList();
      });
    }
  }

  // Save session logs to Local Storage
  Future<void> _saveSessionLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> rawLogs = _sessionLogs.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList('pomodoro_logs', rawLogs);
  }

  // Clear history logs
  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pomodoro_logs');
    setState(() {
      _sessionLogs.clear();
    });
  }
    @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning && _targetEndTime != null) {
      _updateRemainingTime();
    }
  }

  // Generate 880Hz PCM WAV audio bytes for Beep sound
  Uint8List _generateBeepWav() {
    const int sampleRate = 22050;
    const double frequency = 880.0;
    const int durationMs = 600;
    const int numSamples = (sampleRate * durationMs) ~/ 1000;
    const int dataSize = numSamples * 2;
    final int fileSize = 44 + dataSize;

    final ByteData bytes = ByteData(fileSize);

    bytes.setUint32(0, 0x52494646, Endian.big); // "RIFF"
    bytes.setUint32(4, fileSize - 8, Endian.little);
    bytes.setUint32(8, 0x57415645, Endian.big); // "WAVE"

    bytes.setUint32(12, 0x666d7420, Endian.big); // "fmt "
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);

    bytes.setUint32(36, 0x64617461, Endian.big); // "data"
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
    final difference = _targetEndTime!.difference(now).inSeconds;

    setState(() {
      if (difference > 0) {
        _timeLeft = difference;
      } else {
        _playBeepSound();

        if (_isWorkTime) {
          _sessionLogs.insert(
            0,
            SessionEntry(dateTime: DateTime.now(), durationMinutes: _workMinutes),
          );
          _saveSessionLogs();
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
  }
    // NAVIGATION DRAWER (Three-bar Menu with Calendar & History)
  Widget _buildDrawer() {
    final selectedDateSessions = _sessionLogs.where((log) {
      return _isLogOnCalendarDate(log.dateTime, _selectedCalendarDate);
    }).toList();

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.blueAccent),
            accountName: const Text(
              'Pomodoro Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(
              'Lifetime Focus: ${_calculateTotalDuration(_sessionLogs)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.calendar_month, size: 36, color: Colors.blueAccent),
            ),
          ),

          ExpansionTile(
            leading: const Icon(Icons.calendar_today, color: Colors.blueAccent),
            title: Text(
              'Date: ${_formatDateOnly(_selectedCalendarDate)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: const Text('Tap to select a date', style: TextStyle(fontSize: 12, color: Colors.white60)),
            initiallyExpanded: true,
            children: [
              SizedBox(
                height: 300,
                child: CalendarDatePicker(
                  initialDate: _selectedCalendarDate,
                  firstDate: DateTime(2023, 1, 1),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  onDateChanged: (DateTime newDate) {
                    setState(() {
                      _selectedCalendarDate = newDate;
                    });
                  },
                ),
              ),
            ],
          ),

          const Divider(height: 1),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date: ${_formatDateOnly(_selectedCalendarDate)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total Time: ${_calculateTotalDuration(selectedDateSessions)}',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.greenAccent, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (_sessionLogs.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    tooltip: 'Clear All History',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear History'),
                          content: const Text('Are you sure you want to delete all session history?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                _clearHistory();
                                Navigator.pop(ctx);
                              },
                              child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: selectedDateSessions.isEmpty
                ? const Center(
                    child: Text(
                      'No sessions recorded on this date.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    itemCount: selectedDateSessions.length,
                    itemBuilder: (context, index) {
                      final log = selectedDateSessions[index];
                      return ListTile(
                        leading: const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                        title: Text(
                          'Work Session: ${log.durationMinutes} mins',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          _formatDateTime(log.dateTime),
                          style: const TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // PORTRAIT LAYOUT
  Widget _buildPortraitLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
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

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: _isWorkTime ? Colors.redAccent : Colors.green,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _isWorkTime ? 'Work Time' : 'Break Time',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),

        GestureDetector(
          onTap: _showCustomTimeDialog,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _formatTime(_timeLeft),
                  style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '💡 Tap timer to adjust custom minutes',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🍅 Today\'s Sessions: ',
                    style: TextStyle(fontSize: 15, color: Colors.white70),
                  ),
                  Text(
                    '$_todaySessionsCount',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '(Resets daily at 4:00 AM)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),

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
    );
  }

  // LANDSCAPE LAYOUT
  Widget _buildLandscapeLayout() {
    return Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: _isWorkTime ? Colors.redAccent : Colors.green,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  _isWorkTime ? 'Work Time' : 'Break Time',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              GestureDetector(
                onTap: _showCustomTimeDialog,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatTime(_timeLeft),
                        style: const TextStyle(fontSize: 68, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '💡 Tap timer to adjust minutes',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const VerticalDivider(width: 1, color: Colors.white24, indent: 10, endIndent: 10),

        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              GestureDetector(
                onTap: _showCustomTimeDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade800,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueAccent, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Mode: $_workMinutes + $_breakMinutes Min',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '🍅 Today: ',
                          style: TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                        Text(
                          '$_todaySessionsCount',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '(Resets at 04:00 AM)',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 56,
                    icon: Icon(_isRunning ? Icons.pause_circle_filled : Icons.play_circle_fill),
                    color: Colors.blueAccent,
                    onPressed: _isRunning ? _pauseTimer : _startTimer,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    iconSize: 42,
                    icon: const Icon(Icons.replay),
                    color: Colors.grey,
                    onPressed: _resetTimer,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
              } else if (value == 'orientation') {
                _showOrientationDialog();
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
                  value: 'orientation',
                  child: Row(
                    children: [
                      Icon(Icons.screen_rotation, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('Screen Orientation'),
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
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: OrientationBuilder(
            builder: (context, orientation) {
              if (orientation == Orientation.landscape) {
                return _buildLandscapeLayout();
              } else {
                return _buildPortraitLayout();
              }
            },
          ),
        ),
      ),
    );
  }
}
