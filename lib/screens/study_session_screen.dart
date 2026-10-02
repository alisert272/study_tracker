import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StudySessionScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final String? topicId;
  final String? topicName;

  const StudySessionScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    this.topicId,
    this.topicName,
  });

  @override
  State<StudySessionScreen> createState() => _StudySessionScreenState();
}

class _StudySessionScreenState extends State<StudySessionScreen> {
  final _supabase = Supabase.instance.client;
  
  Timer? _timer;
  Duration _duration = Duration.zero;
  String _status = 'starting'; 
  String? _sessionId;
  String? _currentBreakId;

  DateTime? _sessionStartTime;
  Duration _totalBreakDuration = Duration.zero;
  DateTime? _currentBreakStartTime;

 @override
  void initState() {
    super.initState();
    // Sayfaya girildiği anı tam olarak kaydediyoruz
    _sessionStartTime = DateTime.now();
    _status = 'active'; 
    _updateDuration(); // Sayacın 00:00:00 olarak hemen ekrana yansımasını sağla
    _startTimer();
    
    _initSession();
  }

  // Initialize or fetch the active session from the database
 // Initialize or fetch the active session from the database
  Future<void> _initSession() async {
    final userId = _supabase.auth.currentUser!.id;

    try {
      final existingSession = await _supabase
          .from('study_sessions')
          .select()
          .eq('student_id', userId)
          .inFilter('status', ['active', 'paused'])
          .maybeSingle();

      if (existingSession != null) {
        // --- CONFLICT CHECK (ÇAKIŞMA KONTROLÜ) ---
        final existingSubjectId = existingSession['subject_id'] as String;
        final existingTopicId = existingSession['topic_id'] as String?;

        if (existingSubjectId != widget.subjectId || existingTopicId != widget.topicId) {
          // Kullanıcı arka planda başka bir ders açıkken farklı bir derse tıklamış
          _timer?.cancel(); // Yanlışlıkla başlayan sayacı durdur
          
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false, // Dışarı tıklayarak kapatmayı engelle
              builder: (ctx) => AlertDialog(
                title: const Text('Active Session Exists', style: TextStyle(fontWeight: FontWeight.bold)),
                content: const Text('You already have an ongoing study session in the background. Please finish or end it before starting a new one.'),
                actions: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx); // Dialog'u kapat
                      Navigator.pop(context); // Sayfadan çık (Geri dön)
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            );
          }
          return; // Yeni seans oluşturmayı veya yanlış dersi yüklemeyi durdur
        }

        // Eğer AYNİ derse (Türev'e) tekrar tıkladıysa, kaldığı yerden sorunsuzca devam ettir
        _sessionId = existingSession['id'] as String;
        _status = existingSession['status'] as String;
        _sessionStartTime = DateTime.parse(existingSession['started_at'] as String).toLocal();

        final breaks = await _supabase
            .from('study_breaks')
            .select()
            .eq('session_id', _sessionId!)
            .order('started_at', ascending: true);

        _totalBreakDuration = Duration.zero;
        for (var b in breaks) {
          final bStart = DateTime.parse(b['started_at'] as String).toLocal();
          if (b['ended_at'] != null) {
            final bEnd = DateTime.parse(b['ended_at'] as String).toLocal();
            _totalBreakDuration += bEnd.difference(bStart);
          } else {
            _currentBreakId = b['id'] as String;
            _currentBreakStartTime = bStart;
          }
        }

        if (mounted) {
          setState(() {
            _updateDuration();
            if (_status == 'active') {
              _startTimer();
            } else {
              _timer?.cancel();
            }
          });
        }
      } else {
        // YENİ SEANS: Supabase sunucu saatini değil, kronometreyi başlattığımız anı zorluyoruz
        final localStartTime = _sessionStartTime ?? DateTime.now();
        
        final newSession = await _supabase.from('study_sessions').insert({
          'student_id': userId,
          'subject_id': widget.subjectId,
          'topic_id': widget.topicId,
          'status': 'active',
          'started_at': localStartTime.toUtc().toIso8601String(), 
        }).select().single();

        _sessionId = newSession['id'] as String;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing session: $e')),
        );
      }
    }
  }

  // Start the UI timer
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateDuration();
        });
      }
    });
  }

  // Calculate the net study duration
  void _updateDuration() {
    if (_sessionStartTime == null) return;
    
    if (_status == 'paused' && _currentBreakStartTime != null) {
      // If paused, time is frozen at the moment the break started minus previous breaks
      _duration = _currentBreakStartTime!.difference(_sessionStartTime!) - _totalBreakDuration;
    } else {
      // If active, current time minus start time minus all breaks
      _duration = DateTime.now().difference(_sessionStartTime!) - _totalBreakDuration;
    }
  }

 // Pause the session and record a break
  Future<void> _pauseSession() async {
    if (_sessionId == null) return;
    
    setState(() {
      _status = 'paused';
      _currentBreakStartTime = DateTime.now();
      _updateDuration();
      _timer?.cancel();
    });

    try {
      await _supabase.from('study_sessions').update({'status': 'paused'}).eq('id', _sessionId!);
      
      // Kullanıcı ID'sini alıyoruz
      final userId = _supabase.auth.currentUser!.id;
      
      final newBreak = await _supabase.from('study_breaks').insert({
        'session_id': _sessionId,
        'student_id': userId, // Hatanın çözümü: Öğrenci ID'sini de ekliyoruz
      }).select().single();
      
      _currentBreakId = newBreak['id'] as String;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

 // Resume the session and end the current break
  Future<void> _resumeSession() async {
    if (_sessionId == null || _currentBreakId == null) return;
    
    // Mevcut mola ID'sini null yapmadan önce geçici bir değişkene güvenle kopyalıyoruz
    final String breakIdToUpdate = _currentBreakId!;
    
    final breakEnd = DateTime.now();
    if (_currentBreakStartTime != null) {
      _totalBreakDuration += breakEnd.difference(_currentBreakStartTime!);
    }

    setState(() {
      _status = 'active';
      _currentBreakId = null;
      _currentBreakStartTime = null;
      _startTimer();
    });

    try {
      // Veritabanını güncellerken kopyaladığımız güvenli ID'yi kullanıyoruz
      await _supabase.from('study_breaks').update({
        'ended_at': breakEnd.toUtc().toIso8601String()
      }).eq('id', breakIdToUpdate);

      await _supabase.from('study_sessions').update({'status': 'active'}).eq('id', _sessionId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // End the session entirely
  Future<void> _endSession() async {
    if (_sessionId == null) return;
    
    _timer?.cancel();
    final endTime = DateTime.now().toUtc().toIso8601String();

    try {
      // Close the break if we were paused
      if (_status == 'paused' && _currentBreakId != null) {
        await _supabase.from('study_breaks').update({
          'ended_at': endTime
        }).eq('id', _currentBreakId!);
      }

      // Complete the session
      await _supabase.from('study_sessions').update({
        'status': 'completed',
        'ended_at': endTime
      }).eq('id', _sessionId!);

      if (mounted) {
        Navigator.pop(context); // Return to Dashboard
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // Helper to format duration beautifully
  String _formatDuration(Duration duration) {
    if (duration.isNegative) duration = Duration.zero;
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isPaused = _status == 'paused';

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: const Text('Focus Session'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            // Warn before leaving if active
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Leave Session?'),
                content: const Text('Are you sure you want to go back? The session will continue in the background.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    }, 
                    child: const Text('Leave')
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Subject and Topic Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.menu_book_rounded, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.subjectName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade800,
                          ),
                        ),
                        if (widget.topicName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.topicName!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const Spacer(),
            
            // Giant Timer Text
            Text(
              _formatDuration(_duration),
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 72,
                fontWeight: FontWeight.w300,
                color: isPaused ? Colors.grey.shade400 : colorScheme.onBackground,
                fontFeatures: const [
                  // Use tabular figures to prevent timer text from shifting horizontally
                  // if the font supports it.
                  FontFeature.tabularFigures(), 
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Status Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _status == 'starting' 
                    ? Colors.grey.shade200 
                    : (isPaused ? Colors.orange.withOpacity(0.1) : Colors.green.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _status == 'starting' 
                          ? Colors.grey 
                          : (isPaused ? Colors.orange : Colors.green),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _status == 'starting' 
                        ? 'Loading...' 
                        : (isPaused ? 'On Break' : 'Focusing'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _status == 'starting' 
                          ? Colors.grey.shade700 
                          : (isPaused ? Colors.orange.shade700 : Colors.green.shade700),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Action Buttons
            if (_status != 'starting')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Pause/Resume Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isPaused ? _resumeSession : _pauseSession,
                        icon: Icon(isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                        label: Text(isPaused ? 'Resume' : 'Pause'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isPaused ? colorScheme.primary : Colors.orange.shade400,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // End Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('End Session?'),
                              content: const Text('Are you sure you want to finish and save this study session?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _endSession();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade400,
                                  ),
                                  child: const Text('End Session'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.stop_rounded),
                        label: const Text('Finish'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          side: BorderSide(color: Colors.red.shade400, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}