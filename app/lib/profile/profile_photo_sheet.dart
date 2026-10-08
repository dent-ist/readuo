import '../theme/readuo_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'profile_widgets.dart';

Future<ImageSource?> chooseProfilePhoto(BuildContext context) =>
    showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            ReaduoSpacing.screenHorizontal,
            0,
            ReaduoSpacing.screenHorizontal,
            22,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Profile photo',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(sheetContext, ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take a photo'),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(sheetContext, ImageSource.gallery),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Choose from library'),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProfilePhotoAccessScreen(),
                  ),
                ),
                child: const Text('Photo access help'),
              ),
            ],
          ),
        ),
      ),
    );

class ProfilePhotoAccessScreen extends StatelessWidget {
  const ProfilePhotoAccessScreen({super.key});
  @override
  Widget build(BuildContext context) => ProfilePage(
    title: 'Photo access',
    children: [
      const SizedBox(height: 35),
      const Icon(Icons.photo_library_outlined, size: 56),
      const Text(
        'Your photos are unavailable',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 21),
      ),
      const Text(
        'Allow photo access in phone settings, or continue without a photo. Your details stay here.',
        textAlign: TextAlign.center,
      ),
      OutlinedButton(
        onPressed: () async {
          try {
            await const MethodChannel(
              'com.zipdosa.readuo/settings',
            ).invokeMethod<void>('openAppSettings');
          } catch (_) {
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Open Readuo permissions in phone settings.'),
                ),
              );
          }
        },
        child: const Text('Open phone settings'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Continue without a photo'),
      ),
    ],
  );
}
