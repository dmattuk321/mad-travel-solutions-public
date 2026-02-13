import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DispatcherHome extends StatefulWidget {
  final bool isAdmin;
  const DispatcherHome({super.key, this.isAdmin = false});

  @override
  State<DispatcherHome> createState() => _DispatcherHomeState();
}

class _DispatcherHomeState extends State<DispatcherHome> with SingleTickerProviderStateMixin {
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

  bool _isTender(Map<String, dynamic> job) {
    final pt = _s(job['pricingType']).toLowerCase();
    if (pt == 'tender') return true;
    if (job['isTender'] == true) return true;
    return false;
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

    final nested = job[key.replaceAll('Address', '')];
    if (nested is Map) {
      final a = _s(nested['address']);
      if (a.isNotEmpty) return a;
    }
    return '';
  }

  Widget _jobHeaderLine(Map<String, dynamic> job) {
    final dt = _compactDateTime(job);
    final price = _money(job['price']);

    final parts = <String>[];
    if (dt.isNotEmpty) parts.add(dt);
    if (price.isNotEmpty) parts.add(price);

    return Text(
      parts.isEmpty ? 'Job' : parts.join('  •  '),
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
  }

  Widget _jobSummary(Map<String, dynamic> job) {
    final pickup = _getAddress(job, 'pickupAddress');
    final dropoff = _getAddress(job, 'dropoffAddress');
    final notes = _s(job['notes']);
    final pax = _s(job['passengerCount']);
    final flight = _s(job['flightDetails']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pickup.isNotEmpty) Text('Pickup: $pickup'),
        if (dropoff.isNotEmpty) Text('Drop-off: $dropoff'),
        if (pax.isNotEmpty) Text('Passengers: $pax'),
        if (flight.isNotEmpty) Text('Flight: $flight'),
        if (notes.isNotEmpty) Text('Notes: $notes'),
      ],
    );
  }

  Future<void> _awardTenderJob({
    required String jobId,
    required String driverId,
    required String driverName,
    required num price,
  }) async {
    final ref = FirebaseFirestore.instance.collection('jobs').doc(jobId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>;
        if (_s(data['status']) != 'new') return;
        if (data['assignedDriverId'] != null) return;

        tx.update(ref, {
          'assignedDriverId': driverId,
          'assignedDriverName': driverName,
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
          'price': price,
          'pricingType': 'tender',
          'winningBidDriverId': driverId,
          'winningBidPrice': price,
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Awarded to $driverName for £${price.toStringAsFixed(2)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Award failed: $e')),
        );
      }
    }
  }

  Future<void> _showBidsBottomSheet(String jobId) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final bidsQuery = FirebaseFirestore.instance
            .collection('jobs')
            .doc(jobId)
            .collection('bids')
            .orderBy('price', descending: false);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Bids',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: bidsQuery.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final bids = snapshot.data?.docs ?? [];
                      if (bids.isEmpty) {
                        return const Center(child: Text('No bids yet.'));
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: bids.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, i) {
                          final d = bids[i].data();
                          final driverName = _s(d['driverName']);
                          final driverId = _s(d['driverId']);
                          final price = (d['price'] is num) ? (d['price'] as num) : 0;

                          return ListTile(
                            title: Text(driverName.isEmpty ? driverId : driverName),
                            subtitle: Text(driverId),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('£${price.toStringAsFixed(2)}'),
                                const SizedBox(width: 10),
                                ElevatedButton(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await _awardTenderJob(
                                      jobId: jobId,
                                      driverId: driverId,
                                      driverName: driverName.isEmpty ? driverId : driverName,
                                      price: price,
                                    );
                                  },
                                  child: const Text('Award'),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- Tab 1: New Jobs (fixed + tender shown, but tender says "View bids") ----------------
  Widget _newJobsTab() {
    final q = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'new')
        .where('assignedDriverId', isNull: true)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No new jobs.'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final job = doc.data();
            final tender = _isTender(job);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _jobHeaderLine(job),
                    const SizedBox(height: 10),
                    _jobSummary(job),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: tender
                          ? ElevatedButton(
                        onPressed: () => _showBidsBottomSheet(doc.id),
                        child: const Text('View Bids'),
                      )
                          : const Text('Fixed price job (drivers can accept)'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------- Tab 2: Tender Jobs only ----------------
  Widget _tenderJobsTab() {
    final q = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'new')
        .where('assignedDriverId', isNull: true)
        .where('pricingType', isEqualTo: 'tender')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No tender jobs.'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final job = doc.data();

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _jobHeaderLine(job),
                    const SizedBox(height: 10),
                    _jobSummary(job),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: () => _showBidsBottomSheet(doc.id),
                        child: const Text('View Bids / Award'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isAdmin ? 'Dispatcher (Admin)' : 'Dispatcher';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
