import 'package:flutter/material.dart';
import 'package:swavoti/services/app_lock_service.dart';
import 'package:swavoti/services/launcher_service.dart';

enum AppLockPinMode { setup, verify }

class AppLockPinScreen extends StatefulWidget {
  final AppLockPinMode mode;
  final Future<void> Function()? onVerified;

  /// When true (default) the screen pops itself after a successful verify.
  /// Set to false when this screen is embedded as a gate that swaps itself
  /// out (for example in front of the App Lock page).
  final bool popAfterVerify;

  /// Optional text overrides, e.g. "Change your PIN".
  final String? title;
  final String? description;

  const AppLockPinScreen({
    super.key,
    required this.mode,
    this.onVerified,
    this.popAfterVerify = true,
    this.title,
    this.description,
  });

  @override
  State<AppLockPinScreen> createState() => _AppLockPinScreenState();
}

class _AppLockPinScreenState extends State<AppLockPinScreen> {
  static const _minPinLength = AppLockService.minPinLength;
  static const _maxPinLength = AppLockService.maxPinLength;
  String _pin = '';
  String? _firstPin;
  String? _message;
  bool _busy = false;
  bool _confirming = false;
  bool _biometricReady = false;
  bool _biometricInFlight = false;

  bool get _isVerify => widget.mode == AppLockPinMode.verify;

  @override
  void initState() {
    super.initState();
    if (_isVerify) _initBiometric();
  }

  /// Shows the fingerprint button and prompts right away when enabled.
  Future<void> _initBiometric() async {
    final enabled = await AppLockService.isBiometricEnabled();
    if (!mounted || !enabled) return;
    setState(() => _biometricReady = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _authenticateWithBiometric();
    });
  }

  Future<void> _authenticateWithBiometric() async {
    if (_busy || _biometricInFlight) return;
    _biometricInFlight = true;
    final success = await LauncherService.authenticateBiometric(
      title: 'Unlock with biometrics',
      subtitle: 'Verify it\'s you to continue',
      negativeText: 'Use PIN',
    );
    _biometricInFlight = false;
    if (!mounted || !success) return;
    await _completeVerification();
  }

  Future<void> _completeVerification() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onVerified?.call();
      if (widget.popAfterVerify && mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Something went wrong: $error';
        _busy = false;
      });
    }
  }

  String get _title {
    if (widget.title != null) return widget.title!;
    if (_isVerify) return 'Enter your PIN';
    return _confirming ? 'Confirm your PIN' : 'Create your App Lock PIN';
  }

  String get _description {
    if (widget.description != null && !_confirming) return widget.description!;
    if (_isVerify) return 'Enter your PIN to continue';
    return _confirming
        ? 'Enter the same PIN again'
        : 'Choose a PIN with $_minPinLength or more digits';
  }

  void _addDigit(String digit) {
    if (_busy || _pin.length >= _maxPinLength) return;
    setState(() {
      _pin += digit;
      _message = null;
    });
  }

  void _removeDigit() {
    if (_busy || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _message = null;
    });
  }

  Future<void> _continue() async {
    if (_pin.length < _minPinLength || _busy) return;
    setState(() => _busy = true);
    try {
      if (_isVerify) {
        final matches = await AppLockService.verifyPin(_pin);
        if (!mounted) return;
        if (!matches) {
          setState(() {
            _pin = '';
            _message = 'That PIN is incorrect. Try again.';
            _busy = false;
          });
          return;
        }
        setState(() => _busy = false);
        await _completeVerification();
        return;
      }

      if (!_confirming) {
        setState(() {
          _firstPin = _pin;
          _pin = '';
          _confirming = true;
          _busy = false;
        });
        return;
      }

      if (_pin != _firstPin) {
        setState(() {
          _firstPin = null;
          _pin = '';
          _confirming = false;
          _message = 'PINs did not match. Start again.';
          _busy = false;
        });
        return;
      }

      await AppLockService.savePin(_pin);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not securely save or check your PIN: $error';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final numbers = <String?>[
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      _isVerify && _biometricReady ? 'biometric' : null,
      '0',
      'back',
    ];
    final dotCount = _pin.length < _minPinLength ? _minPinLength : _pin.length;

    return Scaffold(
      // Solid background: MainActivity uses a transparent window, so without
      // an explicit colour the wallpaper would show through.
      backgroundColor: colors.surface,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        leading: _isVerify
            ? IconButton(
                tooltip: 'Exit without opening app',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(_isVerify ? 'App locked' : 'App Lock'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _description,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    alignment: WrapAlignment.center,
                    runSpacing: 8,
                    children: List.generate(
                      dotCount,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index < _pin.length
                              ? colors.primary
                              : colors.surfaceContainerHighest,
                          border: Border.all(color: colors.outline),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 42,
                    child: Center(
                      child: _message == null
                          ? null
                          : Text(
                              _message!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.error),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: 270,
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: numbers.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1.35,
                          ),
                      itemBuilder: (context, index) {
                        final value = numbers[index];
                        if (value == null) return const SizedBox.shrink();
                        if (value == 'biometric') {
                          return IconButton.filledTonal(
                            tooltip: 'Unlock with biometrics',
                            onPressed: _authenticateWithBiometric,
                            icon: const Icon(Icons.fingerprint_rounded),
                          );
                        }
                        if (value == 'back') {
                          return IconButton.filledTonal(
                            tooltip: 'Delete digit',
                            onPressed: _removeDigit,
                            icon: const Icon(Icons.backspace_outlined),
                          );
                        }
                        return FilledButton.tonal(
                          onPressed: () => _addDigit(value),
                          child: Text(
                            value,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _pin.length >= _minPinLength && !_busy
                        ? _continue
                        : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      _isVerify
                          ? 'Continue'
                          : _confirming
                          ? 'Save PIN'
                          : 'Next',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
