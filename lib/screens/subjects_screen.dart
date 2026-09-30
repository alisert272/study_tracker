import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  late Future<List<Map<String, dynamic>>> _subjectsFuture;

  @override
  void initState() {
    super.initState();
    _subjectsFuture = _loadSubjects();
  }

  Future<List<Map<String, dynamic>>> _loadSubjects() async {
    final data = await Supabase.instance.client
        .from('subjects')
        .select('id, name')
        .order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  void _refresh() {
    setState(() {
      _subjectsFuture = _loadSubjects();
    });
  }

  Future<void> _addSubject() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ders ekle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Ders adı'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('subjects').insert({
        'student_id': supabase.auth.currentUser!.id,
        'name': name,
      });
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ders eklenemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Derslerim')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSubject,
        icon: const Icon(Icons.add),
        label: const Text('Ders ekle'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _subjectsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Liste yüklenemedi: ${snapshot.error}'));
          }

          final subjects = snapshot.data!;
          if (subjects.isEmpty) {
            return const Center(
              child: Text('Henüz ders yok.\n"Ders ekle" ile başla.',
                  textAlign: TextAlign.center),
            );
          }

          return ListView.builder(
            itemCount: subjects.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(subjects[index]['name'] as String),
              );
            },
          );
        },
      ),
    );
  }
}