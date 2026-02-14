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
  final Map<String, TextEditingController> _bidControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    for (final c in _bidControllers.values) {
      c.dispose();
    }
    _bidControllers.clear();
    _tabController.dispose();
    super.dispose();
  }

  TextEditingController _bidControllerFor(String jobDocId) {
    return _bidControllers.putIfAbsent(jobDocId, () => TextEditingController());
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  String _money(dynamic v) {
    if (v == null) return '';
    if (v is num) return '£${v.toStringAsFixed(2)}';
    final s = v.toString().trim();
    if (s.isEmpty) return '';
    return s.startsWith('£') ? s : '£$s';
  }

  num? _parsePrice(String input) {
    final cleaned = input.trim().replaceAll('£', '');
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
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

  bool _isOfferPendingStatus(String status) {
    // Support BOTH names while you’re transitioning
    return status == 'offer_pending' || status == 'award_pending';
  }

  Timestamp? _getOfferExpiresAt(Map<String, dynamic> job) {
    final v1 = job['offerExpiresAt'];
    if (v1 is Timestamp) return v1;
    final v2 = job['awardExpiresAt'];
    if (v2 is Timestamp) return v2;
    return null;
  }

  bool _offerExpired(Map<String, dynamic> job) {
    final ts = _getOfferExpiresAt(job);
    if (ts == null) return false;
    return ts.toDate().isBefore(DateTime.now());
  }

  // ---------------- FIXED JOB ACCEPT ----------------
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

      if (pricingType.isNotEmpty && pricingType != 'fixed') return;
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

  // ---------------- TENDER BID SUBMIT ----------------
  Future<void> _submitBid(String jobDocId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = _bidControllerFor(jobDocId);
    final price = _parsePrice(controller.text);

    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid bid price (e.g. 25 or 25.50).')),
      );
      return;
    }

    final jobRef = FirebaseFirestore.instance.collection('jobs').doc(jobDocId);
    final jobSnap = await jobRef.get();
    if (!jobSnap.exists) return;

    final job = jobSnap.data() as Map<String, dynamic>;
    final status = _s(job['status']);
    final assigned = job['assignedDriverId'];
    final pricingType = _s(job['pricingType']);

    if (pricingType != 'tender') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This job is not a tender job.')),
      );
      return;
    }
    if (status != 'new' || assigned != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bidding is closed for this job.')),
      );
      return;
    }

    final bidRef = jobRef.collection('bids').doc(user.uid);

    await bidRef.set({
      'driverId': user.uid,
      'driverName': _s(user.email),
      'price': price,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bid submitted: £${price.toStringAsFixed(2)}')),
    );
  }

  // ---------------- OFFER CONFIRM / DECLINE ----------------
  Future<void> _acceptOffer(String jobDocId) async {
    final ref = FirebaseFirestore.instance.collection('jobs').doc(jobDocId);
    await ref.update({
      'status': 'accepted',
      'offerAcceptedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _declineOffer(String jobDocId) async {
    final ref = FirebaseFirestore.instance.collection('jobs').doc(jobDocId);
    await ref.update({
      'status': 'new',
      'assignedDriverId': null,
      'assignedDriverName': null,
      'offerDeclinedAt': FieldValue.serverTimestamp(),
      // Optional cleanup (safe even if fields don’t exist)
      'offerExpiresAt': null,
      'awardExpiresAt': null,
      'offerMinutes': null,
      'awardMinutes': null,
    });
  }

  // ---------------- STATUS UPDATES ----------------
  bool _canMoveTo(String current, String target) {
    if (!_statuses.contains(target)) return false;

    // do NOT allow status buttons when offer is pending
    if (_isOfferPendingStatus(current)) return false;

    if (current == 'new') return target == 'accepted';

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

  // ---------------- UI HELPERS ----------------
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

  Widget _statusButtons(String docId, String currentStatus) {
    if (currentStatus == 'new' || _isOfferPendingStatus(currentStatus)) {
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

  // ---------------- TAB 1: FIXED ----------------
  Widget _availableFixedJobsTab() {
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
        if (docs.isEmpty) {
          return const Center(child: Text('No available fixed price jobs right now.'));
        }

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

  // ---------------- TAB 2: TENDER ----------------
  Widget _tenderJobsTab() {
    final query = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'new')
        .where('assignedDriverId', isNull: true)
        .where('pricingType', isEqualTo: 'tender')
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No tender jobs right now.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final job = doc.data();
            final controller = _bidControllerFor(doc.id);

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
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Your bid (£)',
                              hintText: 'e.g. 25 or 25.50',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => _submitBid(doc.id),
                          child: const Text('Submit Bid'),
                        ),
                      ],
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

  // ---------------- TAB 3: MY JOBS ----------------
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

            final isOfferPending = _isOfferPendingStatus(status);
            final expired = isOfferPending ? _offerExpired(job) : false;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ExpansionTile(
                title: _jobHeaderLine(job),
                subtitle: Text('Status: $status'),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  const SizedBox(height: 8),
                  _jobSummary(job),

                  if (isOfferPending) ...[
                    const SizedBox(height: 12),
                    Text(
                      expired ? 'Offer expired' : 'Offer pending – please confirm',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: expired ? Colors.red : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: expired ? null : () => _acceptOffer(doc.id),
                            icon: const Icon(Icons.check),
                            label: const Text('Accept Offer'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _declineOffer(doc.id),
                            icon: const Icon(Icons.close),
                            label: const Text('Decline Offer'),
                          ),
                        ),
                      ],
                    ),
                  ],

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

  // ---------------- BUILD ----------------
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
            Tab(text: 'Fixed Jobs'),
            Tab(text: 'Tender Jobs'),
            Tab(text: 'My Jobs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _availableFixedJobsTab(),
          _tenderJobsTab(),
          _myJobsTab(),
        ],
      ),
    );
  }
}

