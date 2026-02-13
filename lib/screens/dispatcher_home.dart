import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'add_job_page.dart';

class DispatcherHome extends StatelessWidget {
  final bool isAdmin;
  const DispatcherHome({super.key, this.isAdmin = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isAdmin ? 'Admin – Dispatcher View' : 'Dispatcher'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddJobPage()),
          );
        },
      ),
      body: const Center(
        child: Text('Tap + to create a new job'),
      ),
    );
  }
}