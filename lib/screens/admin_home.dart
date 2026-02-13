import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dispatcher_home.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DispatcherHome(isAdmin: true),
                  ),
                );
              },
              child: const Text('Dispatcher View'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Admin tools coming next…',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}