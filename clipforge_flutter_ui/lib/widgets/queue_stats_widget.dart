import 'package:flutter/material.dart';

/// Widget to display overall queue statistics
class QueueStatsWidget extends StatelessWidget {
  final int totalJobs;
  final int pendingJobs;
  final int runningJobs;
  final int completedJobs;
  final int failedJobs;

  const QueueStatsWidget({
    Key? key,
    required this.totalJobs,
    required this.pendingJobs,
    required this.runningJobs,
    required this.completedJobs,
    required this.failedJobs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Queue Statistics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  icon: Icons.all_inbox,
                  label: 'Total',
                  value: totalJobs.toString(),
                  color: Colors.blue,
                ),
                _buildStatColumn(
                  icon: Icons.schedule,
                  label: 'Pending',
                  value: pendingJobs.toString(),
                  color: Colors.orange,
                ),
                _buildStatColumn(
                  icon: Icons.sync,
                  label: 'Running',
                  value: runningJobs.toString(),
                  color: Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  icon: Icons.check_circle,
                  label: 'Completed',
                  value: completedJobs.toString(),
                  color: Colors.green,
                ),
                _buildStatColumn(
                  icon: Icons.error,
                  label: 'Failed',
                  value: failedJobs.toString(),
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
