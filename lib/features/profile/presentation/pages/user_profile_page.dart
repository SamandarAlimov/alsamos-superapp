import 'package:flutter/material.dart';

import 'profile_page.dart';

/// Legacy route wrapper — delegates to the unified [ProfilePage].
///
/// All `/user/:username` routes resolve through here. The unified ProfilePage
/// handles both UUID and username resolution internally.
class UserProfilePage extends StatelessWidget {
  final String usernameOrId;
  const UserProfilePage({super.key, required this.usernameOrId});

  @override
  Widget build(BuildContext context) {
    return ProfilePage(usernameOrId: usernameOrId);
  }
}
