import 'package:flutter/material.dart';

import 'profile_widgets.dart';

class InformationScreen extends StatelessWidget {
  const InformationScreen({required this.topic, super.key});
  final String topic;

  @override
  Widget build(BuildContext context) {
    final (title, paragraphs) = switch (topic) {
      'camera-denied' => (
        'Scanning help',
        [
          'Allow camera access in your phone’s app settings to scan ISBN barcodes. Use good lighting and hold the book steady.',
          'You can always enter the ISBN, search by title or author, or add a book manually. Camera access is optional.',
        ],
      ),
      'isbn-not-found' => (
        'Find or add a book',
        [
          'Search the catalogue by title or author, then choose the edition whose ISBN matches your book.',
          'If it is not listed, choose Add manually and enter its title and author. An ISBN is optional for manual entries.',
        ],
      ),
      'terms' => (
        'Community guidelines',
        [
          'Readuo is a place to share books and reading with friends. Treat other readers respectfully.',
          'Do not post threats, encouragement to self-harm, harassment, spam, or another person’s private information. Share only content you have permission to share.',
          'Report a post, comment, or profile from its options menu. You can block a reader to stop further interactions. Moderators review reports and can remove content.',
          'For support or review of a moderation decision, contact plogramer.dev@gmail.com.',
        ],
      ),
      _ => (
        'Privacy & shelf visibility',
        [
          'Your display name and optional profile photo identify you to other signed-in readers. Your sign-in email is not part of your public profile.',
          'Private shelves are visible only to you. Friends shelves are visible to accepted friends. Public shelves are visible to any signed-in Readuo reader. Only books marked owned appear in discovery.',
          'Circle is friends-only. Making a shelf private, removing a friend, or blocking a reader revokes the related online access. Blocking also prevents new requests.',
          'Readuo stores account, library, social content, and uploaded images using Firebase. Reports and support messages are available to authorized moderators. Notification preferences control requests, acceptances, likes, and comments.',
          'Contact plogramer.dev@gmail.com for privacy questions or an account-deletion request. Account deletion permanently removes associated data, including reports and security records.',
        ],
      ),
    };
    return ProfilePage(
      title: title,
      children: [
        for (final paragraph in paragraphs)
          Text(paragraph, style: const TextStyle(fontSize: 14, height: 1.6)),
      ],
    );
  }
}
