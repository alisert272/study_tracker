import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';
import 'subjects_screen.dart';
import 'study_session_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  final String fullName;

  const StudentHomeScreen({super.key, required this.fullName});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  late Future<Map<String, dynamic>?> _activeSessionFuture;

  @override
  void initState() {
    super.initState();
    _refreshSession();
  }

  void _refreshSession() {
    setState(() {
      _activeSessionFuture = _getActiveSession();
    });
  }

  Future<Map<String, dynamic>?> _getActiveSession() async {
    final supabase = Supabase.instance.client;
    final response = await supabase
        .from('study_sessions')
        .select('subject_id, topic_id, subjects(name), topics(name)')
        .eq('student_id', supabase.auth.currentUser!.id)
        .eq('status', 'active')
        .maybeSingle();
    return response;
  }

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Future<void> _generateCode(BuildContext context) async {
    try {
      final result = await Supabase.instance.client.rpc('generate_link_code');
      final code = result as String;

      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Eşleştirme Kodu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                code,
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(letterSpacing: 6),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bu kodu ebeveynine ver. 10 dakika geçerli ve tek kullanımlık.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kod kopyalandı')),
                );
              },
              child: const Text('Kopyala'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kod üretilemedi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Öğrenci'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _activeSessionFuture,
        builder: (context, snapshot) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Merhaba ${widget.fullName}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const CircularProgressIndicator()
                else if (snapshot.hasData && snapshot.data != null)
                  Card(
                    color: Colors.green.shade50,
                    margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    child: ListTile(
                      leading: const Icon(Icons.timer, color: Colors.green),
                      title: const Text('Devam eden çalışman var', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      subtitle: Text(snapshot.data!['subjects']['name'] as String),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => StudySessionScreen(
                              subjectId: snapshot.data!['subject_id'] as String,
                              subjectName: snapshot.data!['subjects']['name'] as String,
                              topicId: snapshot.data!['topic_id'] as String?,
                              topicName: snapshot.data!['topics']?['name'] as String?,
                            ),
                          ),
                        ).then((_) => _refreshSession());
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _generateCode(context),
                  icon: const Icon(Icons.link),
                  label: const Text('Ebeveyn bağla'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubjectsScreen()),
                    ).then((_) => _refreshSession());
                  },
                  icon: const Icon(Icons.menu_book),
                  label: const Text('Derslerim'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}