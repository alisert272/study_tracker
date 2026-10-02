import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';

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

    final students = await supabase
        .from('profiles')
        .select('id, full_name')
        .inFilter('id', ids);

    final sessions = await supabase
        .from('study_sessions')
        .select('student_id, started_at, subjects(name), topics(name)')
        .inFilter('student_id', ids)
        .eq('status', 'active');

    return students.map((student) {
      final session = sessions.cast<Map<String, dynamic>>().firstWhere(
            (s) => s['student_id'] == student['id'],
            orElse: () => <String, dynamic>{},
          );
      return {
        'id': student['id'],
        'full_name': student['full_name'],
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
              return StudentTile(student: students[index]);
            },
          );
        },
      ),
    );
  }
}

class StudentTile extends StatefulWidget {
  final Map<String, dynamic> student;

  const StudentTile({Key? key, required this.student}) : super(key: key);

  @override
  State<StudentTile> createState() => _StudentTileState();
}

class _StudentTileState extends State<StudentTile> {
  Timer? _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupTimer();
  }

  @override
  void didUpdateWidget(covariant StudentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.student['active_session'] != widget.student['active_session']) {
      _setupTimer();
    }
  }

  void _setupTimer() {
    _timer?.cancel();
    final session = widget.student['active_session'];
    if (session != null) {
      final startTime = DateTime.parse(session['started_at'] as String).toLocal();
      _duration = DateTime.now().difference(startTime);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _duration = DateTime.now().difference(startTime);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.student['active_session'];

    if (session == null) {
      return ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.grey,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(widget.student['full_name'] as String),
        subtitle: const Text('Şu an çalışmıyor'),
      );
    }

    final subjectData = session['subjects'];
    final subjectName = subjectData != null ? subjectData['name'] as String : 'Bilinmeyen Ders';

    final topicData = session['topics'];
    final topicName = topicData != null ? topicData['name'] as String : null;

    final text = topicName != null ? '$subjectName - $topicName' : subjectName;

    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Colors.green,
        child: Icon(Icons.timer, color: Colors.white),
      ),
      title: Text(widget.student['full_name'] as String),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Çalışıyor: $text', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          Text(_formatDuration(_duration), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}