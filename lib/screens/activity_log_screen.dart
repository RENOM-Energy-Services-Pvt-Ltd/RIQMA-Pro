
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ActivityLogScreen extends StatelessWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications', 
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: currentUser == null
          ? const Center(child: Text('Please log in to view logs'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('activity_logs')
                  .where('userId', isEqualTo: currentUser.uid)
                  .orderBy('timestamp', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No notifications yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final userName = data['userName'] as String? ?? 'Unknown User';
              final description = data['description'] as String? ?? '';
              final timestamp = data['timestamp'] as Timestamp?;
              final actionType = data['actionType'] as String? ?? 'INFO';
              
              var timeText = '';
              if (timestamp != null) {
                timeText = _formatTimestamp(timestamp.toDate());
              }

              IconData icon;
              Color iconColor;
              
              switch (actionType) {
                case 'AUDIT_START':
                  icon = Icons.play_circle_outline;
                  iconColor = Colors.blue;
                  break;
                case 'AUDIT_SUBMIT':
                  icon = Icons.check_circle_outline;
                  iconColor = Colors.green;
                  break;
                case 'LOGIN':
                  icon = Icons.login;
                  iconColor = Colors.teal;
                  break;
                case 'LOGOUT':
                  icon = Icons.logout;
                  iconColor = Colors.grey;
                  break;
                default:
                  icon = Icons.info_outline;
                  iconColor = Colors.orange;
              }

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: iconColor.withValues(alpha: 0.1),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                title: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.black87, fontSize: 14),
                    children: [
                      TextSpan(
                        text: userName, 
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ' '),
                      TextSpan(text: description),
                    ],
                  ),
                ),
                subtitle: Text(
                  timeText,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTimestamp(DateTime date) {
    final localDate = date.toLocal();
    final now = DateTime.now();
    
    // Handle potential future timestamps due to server/device clock drift
    if (localDate.isAfter(now)) {
      return 'Just now';
    }

    final difference = now.difference(localDate);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('dd MMM yyyy, hh:mm a').format(localDate);
    }
  }
}
