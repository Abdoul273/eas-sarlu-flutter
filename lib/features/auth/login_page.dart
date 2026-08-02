import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_state.dart';
import '../../app/ui_kit.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _deviceNomController = TextEditingController();
  bool _obscurePassword = true;
  bool _showCodeSetup = false;
  String? _lastDeviceId;
  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _deviceNomController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _error = null;
      _isSubmitting = true;
    });
    try {
      final authNotifier = ref.read(authStateProvider.notifier);
      await authNotifier.login(
        _emailController.text.trim(),
        _passwordController.text,
        deviceNom: _deviceNomController.text.trim().isEmpty
            ? null
            : _deviceNomController.text.trim(),
      );
      // après login réussi, vérifier aDejaUnCode (info dans la réponse, mais on ne l'a pas ici)
      // On va plutôt interroger l'état : si le serveur renvoie aDejaUnCode = false, on propose de définir un code
      // Malheureusement on n'a pas cette info dans l'état utilisateur. On peut la stocker temporairement.
      // On va modifier le AuthRepository pour renvoyer aussi aDejaUnCode. On ajustera.
      // Pour l'instant, on propose toujours le setup du code si login réussi (ce n'est pas bloquant, le serveur refusera si déjà défini)
      final authRepo = ref.read(authRepositoryProvider);
      final deviceId = await authRepo.getDeviceId();
      // Un login réussi fait rediriger le routeur : cette page peut déjà être
      // démontée quand on revient de l'await.
      if (!mounted) return;
      if (deviceId != null) {
        _lastDeviceId = deviceId;
        setState(() => _showCodeSetup = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('ApiException:', '').trim();
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _defineCode() async {
    final codeController1 = TextEditingController();
    final codeController2 = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Définir votre code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController1,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Code (4-6 chiffres)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController2,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmer le code'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard'),
          ),
          AppButton(
            label: 'Valider',
            onPressed: () async {
              if (codeController1.text != codeController2.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Les codes ne correspondent pas')),
                );
                return;
              }
              if (codeController1.text.length < 4) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Le code doit comporter au moins 4 chiffres')),
                );
                return;
              }
              try {
                await ref.read(authRepositoryProvider).setCode(
                      _lastDeviceId!,
                      codeController1.text,
                    );
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
          ),
        ],
      ),
    );
    if (res == true) {
      // Code défini, on peut laisser le routeur rediriger automatiquement car l'utilisateur est déjà connecté
      setState(() => _showCodeSetup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si on propose le setup de code, on affiche un écran simplifié (l'utilisateur est déjà connecté en arrière-plan)
    if (_showCodeSetup) {
      return Scaffold(
        appBar: AppBar(title: const Text('Code appareil')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                const Text(
                  'Protégez l\'accès avec un code rapide',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                AppButton(
                  label: 'Définir un code',
                  icon: Icons.security,
                  onPressed: _defineCode,
                  expanded: true,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() => _showCodeSetup = false),
                  child: const Text('Plus tard'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          const Color(0xFFC23E00),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.warehouse_rounded,
                      size: 38,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'E.A.S Sarlu',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Gestion du magasin de matériaux',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _deviceNomController,
                    decoration: const InputDecoration(
                      labelText: 'Nom de l\'appareil (optionnel)',
                      prefixIcon: Icon(Icons.phone_android),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 28),
                  AppButton(
                    label: _isSubmitting ? 'Connexion…' : 'Se connecter',
                    icon: _isSubmitting ? null : Icons.arrow_forward_rounded,
                    onPressed: _isSubmitting ? null : _login,
                    expanded: true,
                    loading: _isSubmitting,
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
