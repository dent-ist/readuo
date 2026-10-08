import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/readuo_theme.dart';
import '../widgets/readuo_tab_header.dart';
import '../notifications/notification.dart';
import '../notifications/notification_presentation.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({
    required this.title,
    this.children = const [],
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor = ReaduoColors.background,
    this.actions,
    this.back = true,
    this.subtitle,
    this.onBack,
    this.mainTab = false,
    this.compactHeader = true,
    this.tabActions = const [],
    this.notificationDestination,
    super.key,
  });
  final String title;
  final List<Widget> children;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Color backgroundColor;
  final List<Widget>? actions;
  final bool back;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool mainTab;
  final bool compactHeader;
  final List<ReaduoTabHeaderAction> tabActions;
  final NotificationDestination? notificationDestination;
  double _toolbarHeight(BuildContext context) {
    final width =
        MediaQuery.sizeOf(context).width -
        ReaduoSpacing.screenHorizontal * 2 -
        (back ? 54 : 0) -
        (actions?.length ?? 0) * 48;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          fontSize: compactHeader ? 20 : 28,
          height: 1.15,
          letterSpacing: -.7,
          fontWeight: FontWeight.w500,
        ),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: math.max(1, width));
    final titleHeight = titlePainter.height;
    titlePainter.dispose();
    final subtitleHeight = subtitle == null
        ? 0.0
        : MediaQuery.textScalerOf(context).scale(13) * 1.4;
    return math.max(
      subtitle == null ? (compactHeader ? 64.0 : 76.0) : 100.0,
      titleHeight + subtitleHeight + 32,
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: Theme.of(context).filledButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: Theme.of(context).textButtonTheme.style?.copyWith(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    ),
    child: Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: floatingActionButton,
      appBar: mainTab
          ? ReaduoTabHeader(context: context, title: title, actions: tabActions)
          : AppBar(
              actions: actions,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              toolbarHeight: _toolbarHeight(context),
              titleSpacing: ReaduoSpacing.screenHorizontal,
              title: NotificationDestinationMarker(
                destination: notificationDestination,
                child: Row(
                  children: [
                    if (back) ...[
                      SizedBox.square(
                        dimension: 44,
                        child: IconButton.outlined(
                          tooltip: 'Back',
                          onPressed:
                              onBack ?? () => Navigator.maybePop(context),
                          style: IconButton.styleFrom(
                            side: const BorderSide(color: ReaduoColors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          icon: const Icon(Icons.arrow_back, size: 20),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 10,
                            softWrap: true,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              fontSize: compactHeader ? 20 : 28,
                              height: 1.15,
                              letterSpacing: -.7,
                              fontWeight: FontWeight.w500,
                              color: ReaduoColors.ink,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: ReaduoColors.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: bottomNavigationBar,
      body:
          body ??
          SafeArea(
            top: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                mainTab ? 16 : ReaduoSpacing.screenHorizontal,
                18,
                mainTab ? 16 : ReaduoSpacing.screenHorizontal,
                24,
              ),
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0) const SizedBox(height: 16),
                  children[index],
                ],
              ],
            ),
          ),
    ),
  );
}

class ProfileRow extends StatelessWidget {
  const ProfileRow(
    this.title,
    this.icon, {
    this.subtitle,
    this.onTap,
    this.leadingIcon = false,
    super.key,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool leadingIcon;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ReaduoColors.line)),
      ),
      child: Row(
        children: [
          if (leadingIcon) ...[
            Icon(icon, size: 24, color: ReaduoColors.ink),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: ReaduoColors.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: ReaduoColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            leadingIcon ? Icons.chevron_right_rounded : icon,
            size: 20,
            color: leadingIcon ? ReaduoColors.muted : ReaduoColors.ink,
          ),
        ],
      ),
    ),
  );
}

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.name,
    this.image,
    this.singleInitial = false,
    super.key,
  });
  final String name;
  final ImageProvider? image;
  final bool singleInitial;
  String get _initials {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.first.isEmpty) return '?';
    final first = words.first.characters.first;
    final last = !singleInitial && words.length > 1
        ? words.last.characters.first
        : '';
    return '$first$last'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: 76,
      child: image == null
          ? _fallback()
          : Image(
              image: image!,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => _fallback(),
            ),
    ),
  );
  Widget _fallback() => ColoredBox(
    color: const Color(0xFFEDF0FC),
    child: Center(
      child: Text(
        _initials,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w500,
          color: Color(0xFF4051A2),
        ),
      ),
    ),
  );
}

class ProfileBanner extends StatelessWidget {
  const ProfileBanner(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    decoration: BoxDecoration(
      color: ReaduoColors.accentTint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        height: 1.55,
        color: Color(0xFF304E9F),
      ),
    ),
  );
}

class ProfileField extends StatelessWidget {
  const ProfileField({
    required this.label,
    required this.controller,
    required this.limit,
    this.hint,
    this.lines = 1,
    this.enabled = true,
    super.key,
  });
  final String label;
  final TextEditingController controller;
  final int limit;
  final String? hint;
  final int lines;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: ReaduoColors.ink,
        ),
      ),
      const SizedBox(height: 7),
      TextField(
        controller: controller,
        enabled: enabled,
        maxLength: limit,
        minLines: lines,
        maxLines: lines,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
          color: ReaduoColors.ink,
        ),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFD9E0EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: const BorderSide(color: Color(0xFFD9E0EB)),
          ),
        ),
      ),
    ],
  );
}

Widget profileError(String? error) => error == null
    ? const SizedBox.shrink()
    : Semantics(
        liveRegion: true,
        child: Text(
          error,
          style: const TextStyle(
            color: Color(0xFFAC2C40),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      );

void profileUnavailable(BuildContext context) =>
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This destination is currently unavailable.'),
      ),
    );

Future<T?> openProfilePage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
