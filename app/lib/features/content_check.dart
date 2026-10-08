import 'package:flutter/material.dart';

import '../moderation/content_filter.dart';
import '../moderation/moderation_screens.dart';

Future<bool> checkDraftContent(
  BuildContext context,
  TextEditingController controller,
) async {
  if (BasicContentFilter.check(controller.text).allowed) return true;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (pageContext) => ContentFilteredScreen(
        draftController: controller,
        onEdit: () => Navigator.of(pageContext).pop(),
        onGuidelines: () => showDialog<void>(
          context: pageContext,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Community guidelines'),
            content: const Text(
              'Treat readers respectfully. Do not share threats, encouragement to self-harm, harassment, private information, or spam. Report concerns for moderator review. Contact plogramer.dev@gmail.com for support or to request review of a moderation decision.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return false;
}
