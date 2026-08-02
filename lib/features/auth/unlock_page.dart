import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/auth_repository.dart'; // pour UnlockException
import '../../core/auth/verrou_local.dart'; // longueurCodeRequise / longueurCodeMin
import '../../app/ui_kit.dart';

class UnlockPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> deviceInfo;

  const UnlockPage({super.key, required this.deviceInfo});

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  String? _selectedUserId;
  List<Map<String, dynamic>> _comptes = [];
  String _code = '';
  bool _bloque = false;
  String? _errorMessage;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _comptes =
        List<Map<String, dynamic>>.from(widget.deviceInfo['comptes'] ?? []);
    if (_comptes.isNotEmpty) {
      _selectedUserId = _comptes.first['userId'] as String;
    }
  }

  void _onSelectUser(String userId) {
    setState(() {
      _selectedUserId = userId;
      _code = '';
      _errorMessage = null;
      _bloque = false;
    });
  }

  void _onDigit(String digit) {
    if (_bloque || _isVerifying) return;
    if (digit != 'back' && _code.length >= longueurCodeRequise) return;
    HapticFeedback.selectionClick();
    setState(() {
      _errorMessage = null;
      if (digit == 'back') {
        if (_code.isNotEmpty) {
          _code = _code.substring(0, _code.length - 1);
        }
      } else {
        _code += digit;
      }
    });
    // Le code fait six chiffres : au sixième, il n'y a plus rien à attendre.
    // Une minuterie qui partait dès le quatrième chiffre coupait la saisie de
    // quiconque marquait une hésitation au milieu de son propre code.
    if (_code.length == longueurCodeRequise) _verify();
  }

  Future<void> _verify() async {
    if (_isVerifying ||
        _code.length < longueurCodeMin ||
        _bloque ||
        _selectedUserId == null) {
      return;
    }
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final deviceId = widget.deviceInfo['id'] as String;
      await authRepo.unlock(deviceId, _selectedUserId!, _code);
      // succès → l'état authStateProvider passe à connecté, le routeur redirige
    } on UnlockException catch (e) {
      if (!mounted) return;
      setState(() {
        _code = '';
        _errorMessage = e.message;
        if (e.bloque) {
          _bloque = true;
        } else {
          _errorMessage =
              'Code incorrect — ${e.essaisRestants} essai(s) restant(s)';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur réseau. Veuillez réessayer.';
      });
    } finally {
      // Succès → le routeur a déjà remplacé cette page.
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _comptes.firstWhere(
      (c) => c['userId'] == _selectedUserId,
      orElse: () => _comptes.isNotEmpty ? _comptes.first : {},
    );
    final initials =
        (user['nom'] as String? ?? '?').substring(0, 1).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Déverrouillage'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(authGateProvider.notifier).allerVersLogin();
            },
            child: const Text('Mot de passe'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            if (_comptes.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 90,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _comptes.length,
                    itemBuilder: (ctx, index) {
                      final compte = _comptes[index];
                      final selected = compte['userId'] == _selectedUserId;
                      return GestureDetector(
                        onTap: () => _onSelectUser(compte['userId'] as String),
                        child: Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 12),
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                child: Text(
                                  (compte['nom'] as String)
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: selected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onPrimary
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                compte['nom'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    initials,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              user['nom'] as String? ?? 'Utilisateur',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (_bloque)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.lock,
                        size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 8),
                    const Text(
                      'Code bloqué. Veuillez vous connecter par mot de passe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Se connecter par mot de passe',
                      icon: Icons.login,
                      onPressed: () {
                        ref.read(authGateProvider.notifier).allerVersLogin();
                      },
                    ),
                  ],
                ),
              ),
            if (_errorMessage != null && !_bloque)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (!_bloque)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Code à $longueurCodeRequise chiffres',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            if (!_bloque)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    longueurCodeRequise,
                    (i) => Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _code.length
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
            if (!_bloque)
              Expanded(
                child: _buildNumpad(context),
              ),
            if (_isVerifying)
              const Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      childAspectRatio: 1.5,
      children: [
        ...List.generate(9, (i) => i + 1).map((n) => _numButton(n.toString())),
        // Un appareil enrôlé avant le passage à six chiffres peut encore porter
        // un code de quatre ou cinq : sans cette touche, il n'aurait aucun
        // moyen de valider et son propriétaire resterait dehors.
        if (_code.length >= longueurCodeMin &&
            _code.length < longueurCodeRequise)
          _numButton('valider', icon: Icons.check_rounded, accentue: true)
        else
          _numButton('', empty: true),
        _numButton('0'),
        _numButton('back', icon: Icons.backspace_outlined),
      ],
    );
  }

  Widget _numButton(
    String label, {
    IconData? icon,
    bool empty = false,
    bool accentue = false,
  }) {
    if (empty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: accentue ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: label == 'valider' ? _verify : () => _onDigit(label),
          child: Center(
            child: icon != null
                ? Icon(icon,
                    size: 32, color: accentue ? scheme.onPrimary : null)
                : Text(
                    label,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w500),
                  ),
          ),
        ),
      ),
    );
  }
}
