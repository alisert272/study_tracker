import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';
import 'subjects_screen.dart';
import 'study_session_screen.dart';
import 'history_screen.dart';

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

  // Refresh the active session state
  void _refreshSession() {
    setState(() {
      _activeSessionFuture = _getActiveSession();
    });
  }

  // Fetch the currently active session from the database
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

  // Logout the current user
  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  // Generate a pairing code for the parent
  Future<void> _generateCode(BuildContext context) async {
    try {
      final result = await Supabase.instance.client.rpc('generate_link_code');
      final code = result as String;

      if (!context.mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pairing Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                code,
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(letterSpacing: 6, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 12),
              const Text(
                'Share this code with your parent. It is valid for 10 minutes and for single use.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code copied to clipboard')),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate code: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _activeSessionFuture,
        builder: (context, snapshot) {
          return RefreshIndicator(
            onRefresh: () async => _refreshSession(),
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                // Welcome Header
                Text(
                  'Hello,',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.fullName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onBackground,
                  ),
                ),
                const SizedBox(height: 32),

                // Active Session Card
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (snapshot.hasData && snapshot.data != null)
                  _buildActiveSessionCard(context, snapshot.data!, colorScheme),

                if (snapshot.hasData && snapshot.data != null)
                  const SizedBox(height: 24),

                // Dashboard Action Grid
                Text(
                  'Quick Actions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                  children: [
                    _buildActionCard(
                      context: context,
                      title: 'My Subjects',
                      icon: Icons.menu_book_rounded,
                      color: const Color(0xFF3B82F6), // Blue
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SubjectsScreen()),
                        ).then((_) => _refreshSession());
                      },
                    ),
                    _buildActionCard(
                      context: context,
                      title: 'History',
                      icon: Icons.history_rounded,
                      color: const Color(0xFF10B981), // Green
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HistoryScreen()),
                        );
                      },
                    ),
                    _buildActionCard(
                      context: context,
                      title: 'Link Parent',
                      icon: Icons.family_restroom_rounded,
                      color: const Color(0xFFF59E0B), // Orange
                      onTap: () => _generateCode(context),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget for building the active session alert card
  Widget _buildActiveSessionCard(BuildContext context, Map<String, dynamic> data, ColorScheme colorScheme) {
    final subjectName = data['subjects']['name'] as String;
    final topicName = data['topics']?['name'] as String?;
    final titleText = topicName != null ? '$subjectName - $topicName' : subjectName;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudySessionScreen(
                  subjectId: data['subject_id'] as String,
                  subjectName: data['subjects']['name'] as String,
                  topicId: data['topic_id'] as String?,
                  topicName: data['topics']?['name'] as String?,
                ),
              ),
            ).then((_) => _refreshSession());
          },
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.timer, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Session in Progress',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        titleText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.play_circle_fill, color: Colors.white, size: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widget for building grid action cards
  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade200, width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}