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
  late Future<List<Map<String, dynamic>>> _studentsFuture;

  @override
  void initState() {
    super.initState();
    _studentsFuture = _loadStudents();
  }

  Future<List<Map<String, dynamic>>> _loadStudents() async {
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

    return List<Map<String, dynamic>>.from(students);
  }

  void _refresh() {
    setState(() {
      _studentsFuture = _loadStudents();
    });
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
        future: _studentsFuture,
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
              final student = students[index];
              return ListTile(
                leading: const Icon(Icons.school),
                title: Text(student['full_name'] as String),
              );
            },
          );
        },
      ),
    );
  }
}