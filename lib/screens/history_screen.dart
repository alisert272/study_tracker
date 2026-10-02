import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final Future<List<Map<String, dynamic>>> _historyFuture = _loadHistory();
  late final Future<Map<String, dynamic>> _statsFuture = _loadStats();

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

  Future<Map<String, dynamic>> _loadStats() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;

    final response = await supabase.rpc(
      'get_student_stats',
      params: {'p_student_id': userId},
    );

    if (response != null && (response as List).isNotEmpty) {
      return response[0] as Map<String, dynamic>;
    }
    return {'total_net_seconds': 0, 'total_sessions': 0};
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
      appBar: AppBar(title: const Text('Çalışma Geçmişi ve İstatistikler')),
      body: Column(
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: LinearProgressIndicator(),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const SizedBox.shrink();
              }

              final stats = snapshot.data!;
              final totalSeconds = (stats['total_net_seconds'] as num).toInt();
              final totalSessions = stats['total_sessions'];

              return Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('Toplam Süre', _formatDuration(totalSeconds)),
                    Container(height: 30, width: 1, color: Colors.blue.shade300),
                    _buildStatItem('Tamamlanan Ders', '$totalSessions Seans'),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
      ],
    );
  }
}