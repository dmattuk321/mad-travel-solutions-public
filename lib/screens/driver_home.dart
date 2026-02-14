import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _statuses = const ['accepted', 'started', 'arrived', 'pob', 'completed'];

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

    final nested = job[key.replaceAll('Address', '')];
    if (nested is Map) {
      final a = _s(nested['address']);
      if (a.isNotEmpty) return a;
    }
    return '';
  }

  Future<void> _acceptFixedJob(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('jobs').doc(docId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>;
      final currentStatus = _s(data['status']);
      final assigned = data['assignedDriverId'];
      final pricingType = _s(data['pricingType']);

      if (pricingType != 'fixed') return;
      if (currentStatus != 'new') return;
      if (assigned != null) return;

      tx.update(ref, {
        'assignedDriverId': user.uid,
        'assignedDriverName': _s(user.email),
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _confirmTender(String docId, bool accept) async {
    final ref = FirebaseFirestore.instance.collection('jobs').doc(docId);

    await ref.update({
      'status': accept ? 'accepted' : 'declined',
      if (accept) 'acceptedAt': FieldValue.serverTimestamp(),
      if (!accept) 'declinedAt': FieldValue.serverTimestamp(),
    });
  }

  bool _canMoveTo(String current, String target) {
    if (!_statuses.contains(target)) return false;

    if (current == 'new' || current == 'award_pending' || current == 'declined') {
      return false;
    }

    final currentIndex = _statuses.indexOf(current);
    if (currentIndex == -1) return false;

    final targetIndex = _statuses.indexOf(target);
    if (targetIndex == -1) return false;

    return targetIndex >= currentIndex;
  }

  Future<void> _setStatus(String docId, String targetStatus) async {
    final ref = FirebaseFirestore.instance.collection('jobs').doc(docId);
    final tsField = {
      'accepted': 'acceptedAt',
      'started': 'startedAt',
      'arrived': 'arrivedAt',
      'pob': 'pobAt',
      'completed': 'completedAt',
    }[targetStatus];

    await ref.update({
      'status': targetStatus,
      if (tsField != null) tsField: FieldValue.serverTimestamp(),
    });
  }

  Widget _jobHeaderLine(Map<String, dynamic> job) {
    final dt = _compactDateTime(job);
    final price = _money(job['price']);
    final pricingType = _s(job['pricingType']);
    final awardedBid = _money(job['awardedBidPrice']);

    final parts = <String>[];
    if (dt.isNotEmpty) parts.add(dt);

    if (pricingType == 'tender' && awardedBid.isNotEmpty) {
      parts.add('Bid $awardedBid');
    } else if (price.isNotEmpty) {
      parts.add(price);
    }

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

  Widget _statusButtons(String docId, String currentStatus) {
    if (currentStatus == 'new' || currentStatus == 'award_pending' || currentStatus == 'declined') {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _statuses.map((target) {
        final isCurrent = currentStatus == target;
        final enabled = _canMoveTo(currentStatus, target);

        return ElevatedButton(
          onPressed: (!enabled || isCurrent) ? null : () => _setStatus(docId, target),
          child: Text(target.toUpperCase()),
        );
      }).toList(),
    );
  }

  Widget _awardPendingButtons(String docId, Map<String, dynamic> job) {
    final expiresAt = job['awardExpiresAt'];
    DateTime? expires;
    if (expiresAt is Timestamp) expires = expiresAt.toDate();

    final minutes = _s(job['awardMinutes']);
    final price = _money(job['awardedBidPrice']);

    String subtitle = '';
    if (expires != null) {
      final diff = expires.difference(DateTime.now());
      final minsLeft = diff.inMinutes;
      if (minsLeft >= 0) {
        subtitle = 'Time left: ~${minsLeft} min';
      } else {
        subtitle = 'Offer expired (tell dispatch)';
      }
    } else if (minutes.isNotEmpty) {
      subtitle = 'Time limit: $minutes min';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          'You’ve won this tender${price.isNotEmpty ? " ($price)" : ""}. Confirm now:',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (subtitle.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(subtitle),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _confirmTender(docId, true),
                child: const Text('ACCEPT'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _confirmTender(docId, false),
                child: const Text('DECLINE'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ----------- Available Jobs (only FIXED jobs shown here) -----------
  Widget _availableJobsTab() {
    final query = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'new')
        .where('assignedDriverId', isNull: true)
        .where('pricingType', isEqualTo: 'fixed')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No available fixed-price jobs right now.'));

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
                        onPressed: () => _acceptFixedJob(doc.id),
                        child: const Text('Accept Job'),
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

  // ----------- My Jobs (includes award_pending / accepted etc) -----------
  Widget _myJobsTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Not signed in.'));

    final query = FirebaseFirestore.instance
        .collection('jobs')
        .where('assignedDriverId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No jobs assigned to you yet.'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final job = doc.data();
            final status = _s(job['status']).isEmpty ? 'accepted' : _s(job['status']);

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ExpansionTile(
                title: _jobHeaderLine(job),
                subtitle: Text('Status: $status'),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  const SizedBox(height: 8),
                  _jobSummary(job),

                  if (status == 'award_pending')
                    _awardPendingButtons(doc.id, job),

                  if (status == 'declined')
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'You declined this job. Dispatch will re-offer it.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),

                  const SizedBox(height: 12),
                  _statusButtons(doc.id, status),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Available Jobs'),
            Tab(text: 'My Jobs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _availableJobsTab(),
          _myJobsTab(),
        ],
      ),
    );
  }
}
