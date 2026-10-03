import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _historyFuture;
  
  // Toggle state for the overview card
  bool _showAverages = false; 
  
  // Default weekly goal set to 10 hours (36000 seconds)
  // This will be overwritten when data is fetched from Supabase
  int _weeklyGoalSeconds = 36000; 

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
    _fetchWeeklyGoal(); // Fetch the parent-set goal dynamically
  }

  // --- NEW: Fetch the dynamic weekly goal set by the parent ---
  Future<void> _fetchWeeklyGoal() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      
      // 'profiles' tablosunu kendi veritabanındaki öğrenci tablosunun adıyla değiştirebilirsin
      // Eğer 'users' veya 'students' ise ona göre güncelle
      final response = await _supabase
          .from('profiles') 
          .select('weekly_goal_seconds') 
          .eq('id', userId)
          .maybeSingle();

      if (response != null && response['weekly_goal_seconds'] != null) {
        setState(() {
          _weeklyGoalSeconds = response['weekly_goal_seconds'] as int;
        });
      }
    } catch (e) {
      debugPrint('Error fetching weekly goal: $e');
    }
  }

  // Fetch completed study sessions from Supabase view
  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final userId = _supabase.auth.currentUser!.id;
    final data = await _supabase
        .from('completed_sessions_view')
        .select()
        .eq('student_id', userId)
        .order('started_at', ascending: false);
    
    return List<Map<String, dynamic>>.from(data);
  }

  // Format seconds into readable hours and minutes string
  String _formatDuration(int totalSeconds) {
    if (totalSeconds < 0) totalSeconds = 0;
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    return "${duration.inHours}h ${twoDigitMinutes}m";
  }

  // Generate consistent colors for each subject
  Map<String, Color> _generateSubjectColors(List<Map<String, dynamic>> sessions) {
    final Set<String> uniqueSubjects = {};
    for (var s in sessions) {
      uniqueSubjects.add(s['subject_name'] as String? ?? 'Unknown');
    }

    final palette = [
      const Color(0xFF4F46E5), 
      const Color(0xFF10B981), 
      const Color(0xFFF59E0B), 
      const Color(0xFFEF4444), 
      const Color(0xFF8B5CF6), 
      const Color(0xFF06B6D4), 
    ];

    Map<String, Color> subjectColors = {};
    int index = 0;
    for (var subject in uniqueSubjects) {
      subjectColors[subject] = palette[index % palette.length];
      index++;
    }
    return subjectColors;
  }

  // Calculate subject distribution for the pie chart
  Map<String, double> _calculateSubjectDistribution(List<Map<String, dynamic>> sessions) {
    Map<String, double> distribution = {};
    for (var session in sessions) {
      final subject = session['subject_name'] as String? ?? 'Unknown';
      final seconds = (session['net_seconds'] as num?)?.toDouble() ?? 0.0;
      if (seconds > 0) {
        distribution[subject] = (distribution[subject] ?? 0) + seconds;
      }
    }
    return distribution;
  }

  // Calculate total time spent per topic
  Map<String, int> _calculateTopicTotals(List<Map<String, dynamic>> sessions) {
    Map<String, int> totals = {};
    for (var session in sessions) {
      final subject = session['subject_name'] as String? ?? 'Unknown';
      final topic = session['topic_name'] as String?;
      final key = topic != null ? '$subject - $topic' : subject;
      final seconds = (session['net_seconds'] as num?)?.toInt() ?? 0;
      if (seconds > 0) {
        totals[key] = (totals[key] ?? 0) + seconds;
      }
    }
    return totals;
  }

  // Calculate stacked data for the last 7 days bar chart
  List<Map<String, double>> _calculateWeeklyStackedData(List<Map<String, dynamic>> sessions) {
    List<Map<String, double>> weeklyData = List.generate(7, (_) => {});
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (var session in sessions) {
      final startedAtStr = session['started_at'] as String?;
      if (startedAtStr == null) continue;
      
      final date = DateTime.parse(startedAtStr).toLocal();
      final sessionDay = DateTime(date.year, date.month, date.day);
      final difference = today.difference(sessionDay).inDays;

      if (difference >= 0 && difference < 7) {
        final hours = ((session['net_seconds'] as num?)?.toDouble() ?? 0.0) / 3600.0;
        final subject = session['subject_name'] as String? ?? 'Unknown';
        final dayIndex = 6 - difference; 
        
        weeklyData[dayIndex][subject] = (weeklyData[dayIndex][subject] ?? 0) + hours;
      }
    }
    return weeklyData;
  }

  // Calculate consecutive days studied (Streak)
  int _calculateStreak(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return 0;
    
    Set<String> studyDays = {};
    for (var s in sessions) {
      final dateStr = s['started_at'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.parse(dateStr).toLocal();
      studyDays.add(DateFormat('yyyy-MM-dd').format(date));
    }
    
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(yesterday);
    
    if (!studyDays.contains(todayStr) && !studyDays.contains(yesterdayStr)) {
      return 0; 
    }
    
    int streak = 0;
    DateTime checkDate = studyDays.contains(todayStr) ? today : yesterday;
    
    while (true) {
      final checkStr = DateFormat('yyyy-MM-dd').format(checkDate);
      if (studyDays.contains(checkStr)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  // Calculate total study time for the current week
  int _calculateCurrentWeekSeconds(List<Map<String, dynamic>> sessions) {
    final now = DateTime.now();
    final currentWeekStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    
    int totalCurrentWeek = 0;
    for (var s in sessions) {
      final dateStr = s['started_at'] as String?;
      if (dateStr == null) continue;
      final date = DateTime.parse(dateStr).toLocal();
      if (date.isAfter(currentWeekStart) || date.isAtSameMomentAs(currentWeekStart)) {
        totalCurrentWeek += (s['net_seconds'] as num?)?.toInt() ?? 0;
      }
    }
    return totalCurrentWeek;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        title: const Text('Statistics & History'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final sessions = snapshot.data ?? [];
          
          if (sessions.isEmpty) {
            return const Center(
              child: Text(
                'No completed study sessions yet.\nStart studying to see your stats!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final subjectColors = _generateSubjectColors(sessions);
          final subjectDistribution = _calculateSubjectDistribution(sessions);
          final weeklyStackedData = _calculateWeeklyStackedData(sessions);
          
          final topicTotalsMap = _calculateTopicTotals(sessions);
          final sortedTopics = topicTotalsMap.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          int totalSeconds = 0;
          for (var s in sessions) {
            totalSeconds += (s['net_seconds'] as num?)?.toInt() ?? 0;
          }

          Map<String, List<Map<String, dynamic>>> groupedByDay = {};
          for (var session in sessions) {
            final startedAt = session['started_at'] as String?;
            if (startedAt == null) continue;
            final date = DateTime.parse(startedAt).toLocal();
            final dateKey = DateFormat('yyyy-MM-dd').format(date);
            groupedByDay.putIfAbsent(dateKey, () => []).add(session);
          }
          final sortedDays = groupedByDay.keys.toList()..sort((a, b) => b.compareTo(a));

          final currentStreak = _calculateStreak(sessions);
          final currentWeekSeconds = _calculateCurrentWeekSeconds(sessions);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Motivation Card (Streak & Dynamically Fetched Weekly Goal)
              _buildMotivationCard(theme, currentStreak, currentWeekSeconds),
              const SizedBox(height: 16),

              // Interactive Overview Card
              _buildOverviewCard(theme, totalSeconds, sessions.length, sessions),
              const SizedBox(height: 24),
              
              Text(
                'Last 7 Days',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildStackedBarChartCard(weeklyStackedData, subjectColors, theme),
              
              const SizedBox(height: 24),

              if (subjectDistribution.isNotEmpty) ...[
                Text(
                  'Subject Distribution',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildPieChartCard(subjectDistribution, subjectColors, theme),
                const SizedBox(height: 24),
              ],

              if (sortedTopics.isNotEmpty) ...[
                Text(
                  'Topic Breakdown',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: sortedTopics.map((entry) {
                    return Chip(
                      label: Text('${entry.key}: ${_formatDuration(entry.value)}'),
                      backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                      labelStyle: TextStyle(
                        color: theme.colorScheme.primary, 
                        fontWeight: FontWeight.bold,
                      ),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Expandable Daily Cards
              Text(
                'Daily Study Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...sortedDays.map((dateKey) {
                final daySessions = groupedByDay[dateKey]!;
                return _buildExpandableDailyCard(dateKey, daySessions, subjectColors, theme);
              }).toList(),
              
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  // Build Motivation Card (Streak & Weekly Progress)
  Widget _buildMotivationCard(ThemeData theme, int streak, int currentWeekSeconds) {
    // Avoid division by zero if goal is somehow 0
    double progress = _weeklyGoalSeconds > 0 ? currentWeekSeconds / _weeklyGoalSeconds : 0.0;
    if (progress > 1.0) progress = 1.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  '🔥',
                  style: TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 4),
                Text(
                  '$streak Days',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.deepOrange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Weekly Goal',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    Text(
                      '${_formatDuration(currentWeekSeconds)} / ${_formatDuration(_weeklyGoalSeconds)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress == 1.0 ? Colors.green : theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  progress == 1.0 
                      ? 'Goal crushed! Awesome job! 🎉' 
                      : 'Keep going, you can do it!',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build a native, robust expandable card for each day
  Widget _buildExpandableDailyCard(String dateKey, List<Map<String, dynamic>> daySessions, Map<String, Color> subjectColors, ThemeData theme) {
    final dateObj = DateTime.parse(dateKey);
    final formattedDate = DateFormat('dd MMMM yyyy, EEEE').format(dateObj);

    Map<String, int> dailySubjectTotals = {};
    int dayTotalSeconds = 0;

    for (var s in daySessions) {
      final subject = s['subject_name'] as String? ?? 'Unknown';
      final topic = s['topic_name'] as String?;
      final key = topic != null ? '$subject • $topic' : subject;
      final seconds = (s['net_seconds'] as num?)?.toInt() ?? 0;
      
      dailySubjectTotals[key] = (dailySubjectTotals[key] ?? 0) + seconds;
      dayTotalSeconds += seconds;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.calendar_month_rounded, color: theme.colorScheme.primary, size: 22),
          ),
          title: Text(
            formattedDate,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          subtitle: Text(
            'Total: ${_formatDuration(dayTotalSeconds)}',
            style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
          ),
          iconColor: theme.colorScheme.primary,
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          children: dailySubjectTotals.entries.map((entry) {
            final subjectName = entry.key.split(' • ')[0];
            final subjectColor = subjectColors[subjectName] ?? theme.colorScheme.primary;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: subjectColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.key, 
                            style: TextStyle(
                              fontSize: 14, 
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatDuration(entry.value),
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 13, 
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // Build interactive overview summary card widget
  Widget _buildOverviewCard(ThemeData theme, int totalSeconds, int totalSessions, List<Map<String, dynamic>> sessions) {
    int dailyAvgSeconds = 0;
    int weeklyAvgSeconds = 0;

    if (sessions.isNotEmpty) {
      final earliestSessionStr = sessions.last['started_at'] as String?;
      if (earliestSessionStr != null) {
        final earliestDate = DateTime.parse(earliestSessionStr).toLocal();
        final now = DateTime.now();
        
        final daysSinceStart = now.difference(earliestDate).inDays + 1;
        dailyAvgSeconds = totalSeconds ~/ daysSinceStart;
        
        int totalWeeks = (daysSinceStart / 7.0).ceil();
        weeklyAvgSeconds = totalSeconds ~/ totalWeeks;
      }
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _showAverages = !_showAverages;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _showAverages 
                ? [theme.colorScheme.secondary, theme.colorScheme.secondary.withOpacity(0.8)]
                : [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (_showAverages ? theme.colorScheme.secondary : theme.colorScheme.primary).withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: _showAverages
              ? Row(
                  key: const ValueKey('averages'),
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn('Daily Avg', _formatDuration(dailyAvgSeconds), true),
                    Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                    _buildStatColumn('Weekly Avg', _formatDuration(weeklyAvgSeconds), true),
                  ],
                )
              : Row(
                  key: const ValueKey('totals'),
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn('Total Time', _formatDuration(totalSeconds), true),
                    Container(height: 40, width: 1, color: Colors.white.withOpacity(0.3)),
                    _buildStatColumn('Sessions', totalSessions.toString(), true),
                  ],
                ),
        ),
      ),
    );
  }

  // Build individual stat column
  Widget _buildStatColumn(String label, String value, bool isLight) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: isLight ? Colors.white70 : Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24, 
            fontWeight: FontWeight.bold, 
            color: isLight ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  // Build stacked bar chart card widget for weekly stats
  Widget _buildStackedBarChartCard(List<Map<String, double>> weeklyData, Map<String, Color> subjectColors, ThemeData theme) {
    double maxY = 1.0;
    
    for (var dayData in weeklyData) {
      double dailyTotal = 0;
      dayData.values.forEach((hours) => dailyTotal += hours);
      if (dailyTotal > maxY) maxY = dailyTotal;
    }
    maxY = maxY * 1.2;

    final now = DateTime.now();

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => theme.colorScheme.primary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final int totalSeconds = (rod.toY * 3600).toInt();
                return BarTooltipItem(
                  'Total: ${_formatDuration(totalSeconds)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final dayIndex = value.toInt();
                  final date = now.subtract(Duration(days: 6 - dayIndex));
                  final dayLetter = DateFormat('E').format(date).substring(0, 1);
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      dayLetter,
                      style: TextStyle(
                        color: dayIndex == 6 ? theme.colorScheme.primary : Colors.grey,
                        fontWeight: dayIndex == 6 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  if (value == maxY) return const SizedBox.shrink();
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY / 4).ceilToDouble() > 0 ? (maxY / 4).ceilToDouble() : 1,
            getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          barGroups: weeklyData.asMap().entries.map((entry) {
            final dayIndex = entry.key;
            final dayData = entry.value;

            double currentY = 0;
            List<BarChartRodStackItem> stackItems = [];

            dayData.forEach((subject, hours) {
              final color = subjectColors[subject] ?? Colors.grey;
              stackItems.add(BarChartRodStackItem(currentY, currentY + hours, color));
              currentY += hours;
            });

            return BarChartGroupData(
              x: dayIndex,
              barRods: [
                BarChartRodData(
                  toY: currentY,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  color: Colors.transparent,
                  rodStackItems: stackItems,
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // Build pie chart card widget for subject distribution
  Widget _buildPieChartCard(Map<String, double> subjectDistribution, Map<String, Color> subjectColors, ThemeData theme) {
    List<PieChartSectionData> sections = [];
    List<Widget> legendItems = [];

    subjectDistribution.forEach((subject, seconds) {
      final color = subjectColors[subject] ?? Colors.grey;
      
      sections.add(
        PieChartSectionData(
          color: color,
          value: seconds,
          title: _formatDuration(seconds.toInt()),
          radius: 50,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );

      legendItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(subject, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      );
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            height: 150,
            width: 150,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 30,
                sections: sections,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: legendItems,
            ),
          ),
        ],
      ),
    );
  }
}