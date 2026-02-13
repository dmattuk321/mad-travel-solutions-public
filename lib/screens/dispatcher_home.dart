import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'add_job_page.dart';

class DispatcherHome extends StatefulWidget {
  final bool isAdmin;
  const DispatcherHome({super.key, this.isAdmin = false});

  @override
  State<DispatcherHome> createState() => _DispatcherHomeState();
}

class _DispatcherHomeState extends State<DispatcherHome>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _money(dynamic v) {
    if (v == null) return '';
    if (v is num) return '£${v.toStringAsFixed(2)}';
    final s = v.toString().trim();
    if (s.isEmpty) return '';
    return s.startsWith('£') ? s : '£$s';
  }

  String _compactDateTime(Map<String, dynamic> job) {
    final date = _s(job['pickupDate']);
    final time = _s(job['pickupTime']);
    if (date.isEmpty && time.isEmpty) return '';
    if (date.isEmpty) return time;
    if (time.isEmpty) return date;
    return '$date $time';
  }

  String _getAddress(Map<String, dynamic> job, String key) {
    final flat = _s(job[key]);
    if (flat.isNotEmpty) return flat;

    final nested = job[key.replaceAll('Address', '')]; // pickup / dropoff
    if (nested is Map) {
      final a = _s(nested['address']);
      if (a.isNotEmpty) return a;
    }
    return '';
  }

  Widget _jobCard(DocumentSnapshot<Map<String, dynamic>> doc) {
    final job = doc.data() ?? <String, dynamic>{};

    final dt = _compactDateTime(job);
    final price = _money(job['price']);
    final pickup = _getAddress(job, 'pickupAddress');
    final dropoff = _getAddress(job, 'dropoffAddress');
    final notes = _s(job['notes']);
    final pax = _s(job['passengerCount']);
    final flight = _s(job['flightDetails']);

    final headerParts = <String>[];
    if (dt.isNotEmpty) headerParts.add(dt);
    if (price.isNotEmpty) headerParts.add(price);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              headerParts.isEmpty ? 'Job' : headerParts.join('  •  '),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (pickup.isNotEmpty) Text('Pickup: $pickup'),
            if (dropoff.isNotEmpty) Text('Drop-off: $dropoff'),
            if (pax.isNotEmpty) Text('Passengers: $pax'),
            if (flight.isNotEmpty) Text('Flight: $flight'),
            if (notes.isNotEmpty) Text('Notes: $notes'),
          ],
        ),
      ),
    );
  }

  // ---------------- Tabs ----------------

  Widget _newJobsTab() {
    // Fixed jobs waiting to be accepted
    final query = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'new')
        .where('assignedDriverId', isNull: true)
        .where('pricingType', isEqualTo: 'fixed')
        .orderBy('createdAt', descending: true);

    return _jobsList(query, emptyText: 'No new jobs.');
  }

  Widget _tenderJobsTab() {
    // Tender jobs waiting for bids / awarding
    final query = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'new')
        .where('assignedDriverId', isNull: true)
        .where('pricingType', isEqualTo: 'tender')
        .orderBy('createdAt', descending: true);

    return _jobsList(query, emptyText: 'No tender jobs.');
  }

  Widget _jobsList(Query<Map<String, dynamic>> query, {required String emptyText}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: ${snapshot.error}'),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(child: Text(emptyText));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) => _jobCard(docs[i]),
        );
      },
    );
  }

  void _openAddJob() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddJobPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'Dispatcher (Admin)' : 'Dispatcher'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'New Jobs'),
            Tab(text: 'Tender Jobs'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddJob,
        icon: const Icon(Icons.add),
        label: const Text('Add Job'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _newJobsTab(),
          _tenderJobsTab(),
        ],
      ),
    );
  }
}
