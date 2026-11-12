import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/utils/formatters.dart';
import 'package:liyu_social/core/utils/media_picker.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/core/widgets/media_view.dart';
import 'package:liyu_social/core/widgets/user_avatar.dart';
import 'package:liyu_social/domain/models/media.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Name, bio and avatar.
///
/// A new avatar goes through the same prepare-then-upload pipeline as a post, so
/// changing a profile picture costs the metered user the same few kilobytes it
/// would cost to post one — and offline it is accepted by the queue rather than
/// refused.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();

  UserProfile? _person;
  MediaRef? _avatar;
  bool _seeded = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _seed(UserProfile person) {
    if (_seeded) return;
    _seeded = true;
    _person = person;
    _name.text = person.displayName;
    _bio.text = person.bio;
  }

  Future<void> _pickAvatar() async {
    final messenger = ScaffoldMessenger.of(context);
    final t = context.t;
    final person = _person;
    if (person == null) return;
    setState(() => _busy = true);
    try {
      final files = await pickGalleryImages(maxItems: 1);
      if (files.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      final prepared = await ref.read(mediaRepositoryProvider).prepare(
        files.first,
        maxDimension: 320,
      );
      final uploaded = await ref.read(mediaRepositoryProvider).upload(
        ownerUid: person.uid,
        prepared: prepared,
        purpose: MediaPurpose.avatar,
      );
      if (!mounted) return;
      setState(() {
        _avatar = uploaded;
        _busy = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${t.savingData} ${formatBytes(prepared.originalBytes - prepared.bytes.length)}',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _save() async {
    final t = context.t;
    final person = _person;
    if (person == null) return;
    final displayName = _name.text.trim();
    if (displayName.isEmpty) {
      setState(() => _error = t.required);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).updateProfile(
        person.copyWith(
          displayName: displayName,
          bio: _bio.text.trim(),
          photoUrl: _avatar?.fullUrl ?? _avatar?.thumbUrl ?? person.photoUrl,
        ),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      context.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final text = Theme.of(context).textTheme;
    final person = ref.watch(currentUserProvider).valueOrNull;

    if (person == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.editProfile)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    _seed(person);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.editProfile),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(t.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          ContentShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: _AvatarPicker(
                    person: person,
                    avatar: _avatar,
                    busy: _busy,
                    onTap: _busy ? null : _pickAvatar,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(t.displayName, style: text.labelLarge),
                const SizedBox(height: AppSpacing.s),
                TextField(
                  controller: _name,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: t.displayName,
                    errorText: _error,
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: AppSpacing.l),
                Text(t.aboutMe, style: text.labelLarge),
                const SizedBox(height: AppSpacing.s),
                TextField(
                  controller: _bio,
                  maxLines: 4,
                  minLines: 2,
                  maxLength: 160,
                  decoration: InputDecoration(
                    hintText: t.aboutMe,
                    counterText: '',
                  ),
                ),
                const SizedBox(height: AppSpacing.l),
                Text(
                  person.phone ?? person.email ?? '',
                  style: text.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.person,
    required this.avatar,
    required this.busy,
    required this.onTap,
  });

  final UserProfile person;
  final MediaRef? avatar;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final media = avatar;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.surfaceContainerHighest),
            child: media == null
                ? UserAvatar(name: person.displayName, photoUrl: person.photoUrl, size: 96)
                : MediaView(media: media),
          ),
          const SizedBox(height: AppSpacing.s),
          if (busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(Icons.photo_camera_outlined, size: 20, color: scheme.onSurface.withValues(alpha: 0.6)),
        ],
      ),
    );
  }
}
