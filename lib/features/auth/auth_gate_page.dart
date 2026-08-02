import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_state.dart';
import 'login_page.dart';
import 'unlock_page.dart';

class AuthGatePage extends ConsumerStatefulWidget {
  const AuthGatePage({super.key});

  @override
  ConsumerState<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends ConsumerState<AuthGatePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authGateProvider.notifier).decide();
    });
  }

  @override
  Widget build(BuildContext context) {
    final gateState = ref.watch(authGateProvider);

    switch (gateState.step) {
      case AuthGateStep.initial:
      case AuthGateStep.loading:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warehouse, size: 80, color: Color(0xFFE85D04)),
                SizedBox(height: 16),
                Text(
                  'E.A.S Sarlu',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 32),
                CircularProgressIndicator(),
              ],
            ),
          ),
        );
      case AuthGateStep.login:
        return const LoginPage();
      case AuthGateStep.unlock:
        return UnlockPage(deviceInfo: gateState.deviceInfo!);
    }
  }
}
