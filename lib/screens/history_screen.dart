import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Map<String, dynamic>>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;

    final data = await supabase
        .from('completed_sessions_view')
        .select()
        .eq('student_id', userId)
        .order('started_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  String _formatDate(String isoDate) {
    final date = DateTime.parse(isoDate).toLocal();
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(date.day)}.${twoDigits(date.month)}.${date.year} ${twoDigits(date.hour)}:${twoDigits(date.minute)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Çalışma Geçmişi')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }

          final sessions = snapshot.data!;
          if (sessions.isEmpty) {
            return const Center(
              child: Text(
                'Henüz tamamlanmış bir çalışma yok.',
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView.builder(
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final subjectName = session['subject_name'] as String;
              final topicName = session['topic_name'] as String?;
              final startedAt = session['started_at'] as String;
              final netSeconds = (session['net_seconds'] as num).toInt();

              final titleText = topicName != null ? '$subjectName - $topicName' : subjectName;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.check, color: Colors.white),
                  ),
                  title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(_formatDate(startedAt)),
                  trailing: Text(
                    _formatDuration(netSeconds),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}