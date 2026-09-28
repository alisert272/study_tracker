import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final String fullName;
  final String role;

  const HomeScreen({super.key, required this.fullName, required this.role});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ana Sayfa')),
      body: Center(
        child: Text(
          'Merhaba $fullName\nRolün: $role',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}