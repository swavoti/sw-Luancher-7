import 'package:flutter/material.dart';
import 'package:swavoti/services/app_lock_service.dart';

enum AppLockPinMode { setup, verify }

class AppLockPinScreen extends StatefulWidget {
  final AppLockPinMode mode;
  final Future<void> Function()? onVerified;

  const AppLockPinScreen({
    super.key,
    required this.mode,
    this.onVerified,
  });

  @override
  State<AppLockPinScreen> createState() => _AppLockPinScreenState();
}

class _AppLockPinScreenState extends State<AppLockPinScreen> {
  static const _pinLength = 4;
  String _pin = '';
  String? _firstPin;
  String? _message;
  bool _busy = false;
  bool _confirming = false;

  String get _title {
    if (widget.mode == AppLockPinMode.verify) return 'Enter your PIN';
    return _confirming ? 'Confirm your PIN' : 'Create your App Lock PIN';
  }

  String get _description {
    if (widget.mode == AppLockPinMode.verify) {
      return 'Enter your PIN to continue';
    }
    return _confirming
        ? 'Enter the same 4 digits again'
        : 'Choose a 4-digit PIN to protect your apps';
  }

  void _addDigit(String digit) {
    if (_busy || _pin.length == _pinLength) return;
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
    if (_pin.length != _pinLength || _busy) return;
    setState(() => _busy = true);
    try {
      if (widget.mode == AppLockPinMode.verify) {
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
        await widget.onVerified?.call();
        if (mounted) Navigator.pop(context);
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
      null,
      '0',
      'back',
    ];

    return Scaffold(
      appBar: AppBar(
        leading: widget.mode == AppLockPinMode.verify
            ? IconButton(
                tooltip: 'Exit without opening app',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(widget.mode == AppLockPinMode.verify ? 'App locked' : 'App Lock'),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pinLength,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 9),
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
                    onPressed: _pin.length == _pinLength && !_busy
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
                      widget.mode == AppLockPinMode.verify
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
