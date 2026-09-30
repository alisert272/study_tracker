import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TopicsScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;

  const TopicsScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
  });

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  late Future<List<Map<String, dynamic>>> _topicsFuture;

  @override
  void initState() {
    super.initState();
    _topicsFuture = _loadTopics();
  }

  Future<List<Map<String, dynamic>>> _loadTopics() async {
    final data = await Supabase.instance.client
        .from('topics')
        .select('id, name')
        .eq('subject_id', widget.subjectId)
        .order('name');
    return List<Map<String, dynamic>>.from(data);
  }

  void _refresh() {
    setState(() {
      _topicsFuture = _loadTopics();
    });
  }

  Future<void> _addTopic() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konu ekle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Konu adı'),
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
      await Supabase.instance.client.from('topics').insert({
        'subject_id': widget.subjectId,
        'name': name,
      });
      if (!mounted) return;
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Konu eklenemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.subjectName} - Konular')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addTopic,
        icon: const Icon(Icons.add),
        label: const Text('Konu ekle'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _topicsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Liste yüklenemedi: ${snapshot.error}'));
          }

          final topics = snapshot.data!;
          if (topics.isEmpty) {
            return const Center(
              child: Text('Henüz konu yok.\n"Konu ekle" ile başla.',
                  textAlign: TextAlign.center),
            );
          }

          return ListView.builder(
            itemCount: topics.length,
            itemBuilder: (context, index) {
              return ListTile(
                leading: const Icon(Icons.topic),
                title: Text(topics[index]['name'] as String),
              );
            },
          );
        },
      ),
    );
  }
}