import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudySessionScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final String? topicId;
  final String? topicName;

  const StudySessionScreen({
    Key? key,
    required this.subjectId,
    required this.subjectName,
    this.topicId,
    this.topicName,
  }) : super(key: key);

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends State<StudySessionScreen> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isActive = false;
  String? _sessionId;
  DateTime? _startTime;
  Duration _elapsedDuration = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkActiveSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkActiveSession();
    }
  }

  Future<void> _checkActiveSession() async {
    try {
      final response = await _supabase
          .from('study_sessions')
          .select()
          .eq('student_id', _supabase.auth.currentUser!.id)
          .eq('status', 'active')
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _sessionId = response['id'] as String;
          _isActive = true;
          _startTime = DateTime.parse(response['started_at'] as String).toLocal();
          _isLoading = false;
        });
        _startTimerUI();
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startTimerUI() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_startTime != null && mounted) {
        setState(() {
          _elapsedDuration = DateTime.now().difference(_startTime!);
        });
      }
    });
  }

  Future<void> _startSession() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase.rpc(
        'start_study_session',
        params: {
          'p_subject_id': widget.subjectId,
          'p_topic_id': widget.topicId,
        },
      );

      if (mounted) {
        setState(() {
          _sessionId = response as String;
          _isActive = true;
          _startTime = DateTime.now();
          _isLoading = false;
        });
        _startTimerUI();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _endSession() async {
    setState(() => _isLoading = true);
    try {
      await _supabase.rpc(
        'end_study_session',
        params: {'p_session_id': _sessionId},
      );

      _timer?.cancel();

      if (mounted) {
        setState(() {
          _isActive = false;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Çalışma başarıyla kaydedildi!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Çalışma Odası')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.subjectName,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (widget.topicName != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.topicName!,
                style: const TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 50),
            Text(
              _formatDuration(_elapsedDuration),
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 50),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (!_isActive)
              ElevatedButton.icon(
                onPressed: _startSession,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Başla'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: const TextStyle(fontSize: 20),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _endSession,
                icon: const Icon(Icons.stop),
                label: const Text('Bitir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: const TextStyle(fontSize: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}