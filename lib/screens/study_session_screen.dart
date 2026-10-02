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
  String _status = 'initial';
  String? _sessionId;
  
  DateTime? _startTime;
  DateTime? _pauseStartTime;
  Duration _accumulatedBreakDuration = Duration.zero;
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
      final sessionResponse = await _supabase
          .from('study_sessions')
          .select()
          .eq('student_id', _supabase.auth.currentUser!.id)
          .inFilter('status', ['active', 'paused'])
          .maybeSingle();

      if (sessionResponse != null && mounted) {
        final sessionId = sessionResponse['id'] as String;
        final status = sessionResponse['status'] as String;
        final startTime = DateTime.parse(sessionResponse['started_at'] as String).toLocal();

        final breaksResponse = await _supabase
            .from('study_breaks')
            .select()
            .eq('session_id', sessionId);

        Duration calcBreak = Duration.zero;
        DateTime? pStart;

        for (var b in breaksResponse) {
          final bStart = DateTime.parse(b['started_at'] as String).toLocal();
          if (b['ended_at'] != null) {
            final bEnd = DateTime.parse(b['ended_at'] as String).toLocal();
            calcBreak += bEnd.difference(bStart);
          } else {
            pStart = bStart;
          }
        }

        setState(() {
          _sessionId = sessionId;
          _status = status;
          _startTime = startTime;
          _accumulatedBreakDuration = calcBreak;
          _pauseStartTime = pStart;
          _isLoading = false;

          if (_status == 'paused' && _pauseStartTime != null) {
            _elapsedDuration = _pauseStartTime!.difference(_startTime!) - _accumulatedBreakDuration;
          }
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
      if (_startTime != null && _status == 'active' && mounted) {
        setState(() {
          _elapsedDuration = DateTime.now().difference(_startTime!) - _accumulatedBreakDuration;
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
          _status = 'active';
          _startTime = DateTime.now();
          _accumulatedBreakDuration = Duration.zero;
          _pauseStartTime = null;
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

  Future<void> _pauseSession() async {
    setState(() => _isLoading = true);
    try {
      await _supabase.rpc('pause_study_session', params: {'p_session_id': _sessionId});
      if (mounted) {
        setState(() {
          _status = 'paused';
          _pauseStartTime = DateTime.now();
          _elapsedDuration = _pauseStartTime!.difference(_startTime!) - _accumulatedBreakDuration;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  Future<void> _resumeSession() async {
    setState(() => _isLoading = true);
    try {
      await _supabase.rpc('resume_study_session', params: {'p_session_id': _sessionId});
      if (mounted) {
        setState(() {
          _status = 'active';
          if (_pauseStartTime != null) {
            _accumulatedBreakDuration += DateTime.now().difference(_pauseStartTime!);
            _pauseStartTime = null;
          }
          _isLoading = false;
        });
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
      await _supabase.rpc('end_study_session', params: {'p_session_id': _sessionId});
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _status = 'initial';
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
    if (duration.isNegative) duration = Duration.zero;
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
            const SizedBox(height: 30),
            if (_status == 'active')
              const Text('Çalışılıyor...', style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold))
            else if (_status == 'paused')
              const Text('Molada', style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Text(
              _formatDuration(_elapsedDuration),
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: _status == 'paused' ? Colors.grey : Colors.black,
              ),
            ),
            const SizedBox(height: 50),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_status == 'initial')
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_status == 'active')
                    ElevatedButton.icon(
                      onPressed: _pauseSession,
                      icon: const Icon(Icons.pause),
                      label: const Text('Mola Ver'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                    )
                  else if (_status == 'paused')
                    ElevatedButton.icon(
                      onPressed: _resumeSession,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Devam Et'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                    ),
                  const SizedBox(width: 20),
                  ElevatedButton.icon(
                    onPressed: _endSession,
                    icon: const Icon(Icons.stop),
                    label: const Text('Bitir'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}