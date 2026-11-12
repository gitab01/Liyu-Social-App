import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liyu_social/core/l10n/app_strings.dart';
import 'package:liyu_social/core/providers/app_providers.dart';
import 'package:liyu_social/core/theme/app_theme.dart';
import 'package:liyu_social/core/widgets/layout.dart';
import 'package:liyu_social/data/local/seed_content.dart';
import 'package:liyu_social/domain/models/user.dart';
import 'package:liyu_social/domain/repositories/repositories.dart';

/// Sign-in, code entry, and first-run registration in one flow.
///
/// Phone is the primary path because it is the one credential Ethiopian users
/// already have and the one Firebase can issue without an email round-trip.
/// The code step never claims a message was sent when it was not: the local
/// backend has no SMS gateway, so it shows the code it minted instead.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

enum _Step { phone, code, email, register }

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  _Step _step = _Step.phone;
  OtpChallenge? _challenge;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The submit buttons are enabled from the controllers' current text, so a
    // keystroke has to rebuild this state — otherwise a button that starts
    // disabled never notices the typing that should enable it.
    for (final controller in [_phone, _code, _email, _password, _name]) {
      controller.addListener(_onTextChanged);
    }
    // The local backend is seeded with a demo account; prefilling its number
    // turns "how do I try this" into one tap.
    if (ref.read(backendModeProvider) == BackendMode.local) {
      _phone.text = localDemoPhone();
    }
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _looksValid => RegExp(r'^\+?\d[\d\s().-]{8,19}$').hasMatch(_phone.text.trim());

  Future<void> _run(Future<UserProfile> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      // The router redirect owns what happens next; this screen only clears its
      // own spinner, so a slow authState emission cannot leave the button dead.
      if (mounted) setState(() => _busy = false);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _showError(error);
      }
    }
  }

  void _showError(Object error) {
    final text = error is StateError ? error.message : error.toString();
    setState(() => _error = text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendOtp() async {
    if (!_looksValid) {
      setState(() => _error = context.t.invalidPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await ref.read(authRepositoryProvider).sendOtp(_phone.text.trim());
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _step = _Step.code;
        _busy = false;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _busy = false);
      _showError(error);
    }
  }

  Future<void> _verify() => _run(
    () => ref
        .read(authRepositoryProvider)
        .signInWithOtp(challenge: _challenge!, code: _code.text),
  );

  Future<void> _emailSignIn() => _run(
    () => ref
        .read(authRepositoryProvider)
        .signInWithEmail(email: _email.text.trim(), password: _password.text),
  );

  Future<void> _register() => _run(
    () => ref.read(authRepositoryProvider).register(
      displayName: _name.text.trim(),
      phone: _looksValid ? _phone.text.trim() : null,
      languageCode: Localizations.localeOf(context).languageCode,
    ),
  );

  void _goTo(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final local = ref.watch(backendModeProvider) == BackendMode.local;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          child: ContentShell(
            maxWidth: 460,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                Text(t.appName, style: text.displaySmall),
                const SizedBox(height: AppSpacing.s),
                Text(t.signInSubtitle, style: text.bodyMedium),
                const SizedBox(height: AppSpacing.xxl),
                if (_step == _Step.phone) _phoneStep(t, scheme),
                if (_step == _Step.code) _codeStep(t, scheme),
                if (_step == _Step.email) _emailStep(t, scheme),
                if (_step == _Step.register) _registerStep(t, scheme),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.m),
                  Text(_error!, style: text.bodySmall?.copyWith(color: scheme.error)),
                ],
                if (local && _step != _Step.register) ...[
                  const SizedBox(height: AppSpacing.xl),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _goTo(_Step.register),
                    child: Text(t.createAccount),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneStep(L10n t, ColorScheme scheme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t.phone, style: textLabel(context)),
      const SizedBox(height: AppSpacing.s),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s().-]'))],
        decoration: const InputDecoration(hintText: '+251 9…'),
        onSubmitted: (_) => _sendOtp(),
      ),
      const SizedBox(height: AppSpacing.l),
      FilledButton(
        onPressed: _busy || !_looksValid ? null : _sendOtp,
        child: _busy ? const _InlineSpinner() : Text(t.continueWithPhone),
      ),
      const SizedBox(height: AppSpacing.s),
      TextButton(onPressed: _busy ? null : () => _goTo(_Step.email), child: Text(t.orUseEmail)),
    ],
  );

  Widget _codeStep(L10n t, ColorScheme scheme) {
    final challenge = _challenge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${t.codeSentTo} ${_phone.text.trim()}', style: textLabel(context)),
        const SizedBox(height: AppSpacing.s),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          decoration: InputDecoration(hintText: t.enterCode),
          onSubmitted: (_) => _verify(),
        ),
        if (challenge?.devCode != null) ...[
          const SizedBox(height: AppSpacing.m),
          // Not a joke and not a fallback: this backend cannot send SMS, so the
          // code is shown rather than invented.
          Container(
            padding: const EdgeInsets.all(AppSpacing.m),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outline),
            ),
            child: Text('${t.devCodeHint} ${challenge!.devCode}', style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
        const SizedBox(height: AppSpacing.l),
        FilledButton(
          onPressed: _busy || _code.text.trim().length < 6 ? null : _verify,
          child: _busy ? const _InlineSpinner() : Text(t.verify),
        ),
        TextButton(onPressed: _busy ? null : () => _goTo(_Step.phone), child: Text(t.tryAgain)),
      ],
    );
  }

  Widget _emailStep(L10n t, ColorScheme scheme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t.email, style: textLabel(context)),
      const SizedBox(height: AppSpacing.s),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(hintText: 'you@example.com'),
      ),
      const SizedBox(height: AppSpacing.m),
      Text(t.password, style: textLabel(context)),
      const SizedBox(height: AppSpacing.s),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(),
        onSubmitted: (_) => _emailSignIn(),
      ),
      const SizedBox(height: AppSpacing.l),
      FilledButton(onPressed: _busy ? null : _emailSignIn, child: _busy ? const _InlineSpinner() : Text(t.signIn)),
      TextButton(onPressed: _busy ? null : () => _goTo(_Step.phone), child: Text(t.phone)),
    ],
  );

  Widget _registerStep(L10n t, ColorScheme scheme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t.displayName, style: textLabel(context)),
      const SizedBox(height: AppSpacing.s),
      TextField(controller: _name, decoration: const InputDecoration()),
      const SizedBox(height: AppSpacing.m),
      Text(t.phone, style: textLabel(context)),
      const SizedBox(height: AppSpacing.s),
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(hintText: '+251 9…'),
      ),
      const SizedBox(height: AppSpacing.l),
      FilledButton(
        onPressed: _busy || _name.text.trim().isEmpty ? null : _register,
        child: _busy ? const _InlineSpinner() : Text(t.signUp),
      ),
      TextButton(onPressed: _busy ? null : () => _goTo(_Step.phone), child: Text(t.signIn)),
    ],
  );
}

/// Field label kept above every input across the app.
TextStyle? textLabel(BuildContext context) =>
    Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7));

class _InlineSpinner extends StatelessWidget {
  const _InlineSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
