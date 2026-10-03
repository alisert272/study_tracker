import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';
import 'student_history_screen.dart';

class ParentHomeScreen extends StatefulWidget {
  final String fullName;

  const ParentHomeScreen({super.key, required this.fullName});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  late Future<List<Map<String, dynamic>>> _studentsDataFuture;
  late final RealtimeChannel _channel;

  @override
  void initState() {
    super.initState();
    _studentsDataFuture = _loadStudentsData();

    _channel = Supabase.instance.client
        .channel('public:study_sessions')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'study_sessions',
            callback: (payload) {
              _refresh();
            })
        .subscribe();
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(_channel);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadStudentsData() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;

    final links = await supabase
        .from('parent_student_links')
        .select('student_id')
        .eq('parent_id', userId);

    final ids = links.map((l) => l['student_id'] as String).toList();
    if (ids.isEmpty) return [];

    // ÖNEMLİ GÜNCELLEME: Öğrencinin haftalık hedefini (weekly_goal_seconds) de çekiyoruz.
    final students = await supabase
        .from('profiles')
        .select('id, full_name, weekly_goal_seconds')
        .inFilter('id', ids);

    final sessions = await supabase
        .from('study_sessions')
        .select('id, student_id, started_at, status, subjects(name), topics(name)')
        .inFilter('student_id', ids)
        .inFilter('status', ['active', 'paused']);

    final sessionIds = sessions.map((s) => s['id'] as String).toList();
    List<Map<String, dynamic>> allBreaks = [];
    
    if (sessionIds.isNotEmpty) {
      final breaksData = await supabase
          .from('study_breaks')
          .select('session_id, started_at, ended_at')
          .inFilter('session_id', sessionIds);
      allBreaks = List<Map<String, dynamic>>.from(breaksData);
    }

    return students.map((student) {
      final session = sessions.cast<Map<String, dynamic>>().firstWhere(
            (s) => s['student_id'] == student['id'],
            orElse: () => <String, dynamic>{},
          );

      if (session.isNotEmpty) {
        session['breaks'] = allBreaks.where((b) => b['session_id'] == session['id']).toList();
      }

      return {
        'id': student['id'],
        'full_name': student['full_name'],
        'weekly_goal_seconds': student['weekly_goal_seconds'], // Hedef bilgisi eklendi
        'active_session': session.isEmpty ? null : session,
      };
    }).toList();
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        _studentsDataFuture = _loadStudentsData();
      });
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Future<void> _addStudent() async {
    final controller = TextEditingController();

    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Öğrenci ekle'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '6 haneli kod'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Bağlan'),
          ),
        ],
      ),
    );

    if (code == null || code.isEmpty) return;

    try {
      final response = await Supabase.instance.client
          .rpc('redeem_link_code', params: {'p_code': code});
      final result = response as Map<String, dynamic>;

      if (!mounted) return;

      String message;
      if (result['status'] == 'ok') {
        message = '${result['student_name']} ile bağlandın';
        _refresh();
      } else if (result['status'] == 'too_many_attempts') {
        message = 'Çok fazla yanlış deneme. 15 dakika sonra tekrar dene.';
      } else {
        message = 'Kod geçersiz, süresi dolmuş veya kullanılmış.';
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ebeveyn'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStudent,
        icon: const Icon(Icons.person_add),
        label: const Text('Öğrenci ekle'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _studentsDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Liste yüklenemedi: ${snapshot.error}'));
          }

          final students = snapshot.data!;
          if (students.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Henüz bağlı öğrenci yok.\nÖğrenciden kod isteyip "Öğrenci ekle" ile bağlan.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: students.length,
            itemBuilder: (context, index) {
              return StudentTile(
                student: students[index],
                onRefresh: _refresh, 
              );
            },
          );
        },
      ),
    );
  }
}

class StudentTile extends StatefulWidget {
  final Map<String, dynamic> student;
  final VoidCallback onRefresh;

  const StudentTile({Key? key, required this.student, required this.onRefresh}) : super(key: key);

  @override
  State<StudentTile> createState() => _StudentTileState();
}

class _StudentTileState extends State<StudentTile> {
  Timer? _timer;
  Duration _duration = Duration.zero;
  String _status = 'active';

  @override
  void initState() {
    super.initState();
    _setupTimer();
  }

  @override
  void didUpdateWidget(covariant StudentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _setupTimer();
  }

  void _setupTimer() {
    _timer?.cancel();
    final session = widget.student['active_session'];
    
    if (session != null) {
      _status = session['status'] as String;
      final startTime = DateTime.parse(session['started_at'] as String).toLocal();
      final breaks = session['breaks'] as List<dynamic>? ?? [];

      Duration calcBreak = Duration.zero;
      DateTime? pStart;

      for (var b in breaks) {
        final bStart = DateTime.parse(b['started_at'] as String).toLocal();
        if (b['ended_at'] != null) {
          final bEnd = DateTime.parse(b['ended_at'] as String).toLocal();
          calcBreak += bEnd.difference(bStart);
        } else {
          pStart = bStart;
        }
      }

      if (_status == 'paused' && pStart != null) {
        if (mounted) {
          setState(() {
            _duration = pStart!.difference(startTime) - calcBreak;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _duration = DateTime.now().difference(startTime) - calcBreak;
          });
        }
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _duration = DateTime.now().difference(startTime) - calcBreak;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative) duration = Duration.zero;
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  // YENİ: Ebeveynin hedef belirleyeceği iletişim kutusunu (Slider) açan metod (Maks 100 saat)
  Future<void> _setWeeklyGoal() async {
    final studentId = widget.student['id'] as String;
    
    final currentGoalSeconds = widget.student['weekly_goal_seconds'] as int? ?? 36000;
    
    double currentGoalHours = (currentGoalSeconds / 3600).clamp(1.0, 100.0);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('${widget.student['full_name']} İçin Hedef'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Haftalık Hedef: ${currentGoalHours.toInt()} Saat',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: currentGoalHours,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '${currentGoalHours.toInt()} Saat',
                    activeColor: Theme.of(context).colorScheme.primary,
                    onChanged: (val) {
                      setDialogState(() {
                        currentGoalHours = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final newGoalSeconds = (currentGoalHours * 3600).toInt();
                      await Supabase.instance.client
                          .from('profiles')
                          .update({'weekly_goal_seconds': newGoalSeconds})
                          .eq('id', studentId);

                      if (!mounted) return;
                      Navigator.pop(context); 
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Haftalık hedef başarıyla güncellendi!')),
                      );
                      
                      widget.onRefresh(); 
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Hata: $e')),
                      );
                    }
                  },
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.student['active_session'];
    final studentId = widget.student['id'] as String;
    final studentName = widget.student['full_name'] as String;

    final subjectData = session != null ? session['subjects'] : null;
    final subjectName = subjectData != null ? subjectData['name'] as String : 'Bilinmeyen Ders';

    final topicData = session != null ? session['topics'] : null;
    final topicName = topicData != null ? topicData['name'] as String : null;

    final text = session != null ? (topicName != null ? '$subjectName - $topicName' : subjectName) : 'Şu an çalışmıyor';
    final isPaused = _status == 'paused';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: session == null ? Colors.grey : (isPaused ? Colors.orange : Colors.green),
                child: Icon(session == null ? Icons.person : (isPaused ? Icons.pause : Icons.timer), color: Colors.white),
              ),
              title: Text(studentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: session == null
                  ? const Text('Şu an çalışmıyor')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          isPaused ? 'Molada: $text' : 'Çalışıyor: $text',
                          style: TextStyle(
                            color: isPaused ? Colors.orange : Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatDuration(_duration),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: isPaused ? Colors.grey : Colors.black,
                          ),
                        ),
                      ],
                    ),
            ),
            const Divider(),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _setWeeklyGoal,
                  icon: const Icon(Icons.flag, size: 18, color: Colors.deepOrange),
                  label: const Text('Hedef Belirle', style: TextStyle(color: Colors.deepOrange)),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentHistoryScreen(
                          studentId: studentId,
                          studentName: studentName,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Geçmişi Gör'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}