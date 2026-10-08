import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/readuo_theme.dart';

enum ReaduoNavDestination { circle, library, friends, profile }

class ReaduoBottomNavigation extends StatelessWidget {
  const ReaduoBottomNavigation({
    this.active = ReaduoNavDestination.library,
    this.onCircle,
    this.onLibrary,
    this.onFriends,
    this.onProfile,
    super.key,
  });

  final ReaduoNavDestination active;
  final VoidCallback? onCircle;
  final VoidCallback? onLibrary;
  final VoidCallback? onFriends;
  final VoidCallback? onProfile;

  void _unavailable(BuildContext context, String destination) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$destination is coming later.')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 64 + MediaQuery.textScalerOf(context).scale(11) * 1.5,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(
          color: ReaduoColors.paper,
          border: Border(top: BorderSide(color: ReaduoColors.line)),
        ),
        child: Row(
          children: [
            _NavItem(
              key: const Key('nav-circle'),
              icon: LucideIcons.waypoints,
              label: 'Circle',
              selected: active == ReaduoNavDestination.circle,
              onTap: onCircle ?? () => _unavailable(context, 'Circle'),
            ),
            _NavItem(
              key: const Key('nav-library'),
              icon: LucideIcons.libraryBig,
              label: 'Library',
              selected: active == ReaduoNavDestination.library,
              onTap: onLibrary,
            ),
            _NavItem(
              key: const Key('nav-friends'),
              icon: LucideIcons.usersRound,
              label: 'Friends',
              selected: active == ReaduoNavDestination.friends,
              onTap: onFriends ?? () => _unavailable(context, 'Friends'),
            ),
            _NavItem(
              key: const Key('nav-profile'),
              icon: LucideIcons.userRound,
              label: 'Profile',
              selected: active == ReaduoNavDestination.profile,
              onTap: onProfile ?? () => _unavailable(context, 'Profile'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? ReaduoColors.accent : ReaduoColors.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          selected: selected,
          button: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 32,
                decoration: BoxDecoration(
                  color: selected
                      ? ReaduoColors.accentTint
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
