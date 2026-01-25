import 'package:intl/intl.dart';

class DateFormatter {
  /// Format a conversation's date for the conversation list
  /// Shows: "Today", "Yesterday", "X days ago", or "MMM d, yyyy"
  static String formatConversationDate(DateTime updatedAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final conversationDate = DateTime(
      updatedAt.year,
      updatedAt.month,
      updatedAt.day,
    );
    final difference = today.difference(conversationDate).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return '$difference days ago';
    } else {
      // For dates older than a week, show formatted date
      return DateFormat('MMM d, yyyy').format(updatedAt);
    }
  }

  /// Format a message timestamp for the chat screen
  /// Shows: time for today, "Yesterday", "X days ago", or "MMM d, yyyy"
  static String formatMessageTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );
    final difference = today.difference(messageDate).inDays;

    if (difference == 0) {
      // Today - show time only
      return DateFormat('h:mm a').format(timestamp);
    } else if (difference == 1) {
      return 'Yesterday';
    } else if (difference < 7) {
      return '$difference days ago';
    } else {
      // For dates older than a week, show formatted date
      return DateFormat('MMM d, yyyy').format(timestamp);
    }
  }
}
