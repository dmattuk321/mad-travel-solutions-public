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

  num? _parsePrice(String input) {
    final cleaned = input.replaceAll('£', '').trim();
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
  }

  bool _isTender(Map<String, dynamic> job) {
    final pt = _s(job['pricingType']).toLowerCase(); // "fixed" or "tender"
    if (pt == 'tender') return true;
    if (job['isTender'] == true) return true; // backward compat
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

    final nested = job[key.replaceAll('Address', '')]; // pickup / dropoff
    if (nested is Map) {
      final a = _s(nested['address']);
      if (a.isNotEmpty) return a;
    }
    return '';
  }

  Future<void> _acceptJob(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('jobs').doc(docId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>;
        final currentStatus = _s(data['status']);
        final assigned = data['assignedDriverId'];

        // Only accept if truly unassigned & new
        if (currentStatus != 'new') return;
        if (assigned != null) return;

        tx.update(ref, {
          'assignedDriverId': user.uid,
          'assignedDriverName': _s(user.email),
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accept failed: $e')),
        );
      }
    }
  }

  Future<void> _submitBid({
    required String jobId,
    required num price,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final bidRef = FirebaseFirestore.instance
        .collection('jobs')
        .doc(jobId)
        .collection('bids')
        .doc(user.uid);

    try {
      await bidRef.set({
        'driverId': user.uid,
        'driverName': _s(user.email),
        'price': price,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(), // overwritten first time, harmless later
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bid submitted: £${price.toStringAsFixed(2)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bid failed: $e')),
        );
      }
    }
  }

  bool _canMoveTo(String current, String target) {
    if (!_statuses.contains(target)) return false;

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

    try {
      await ref.update({
        'status': targetStatus,
        if (tsField != null) tsField: FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: $e')),
        );
      }
    }
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

  Widget _statusButtons(String docId, String currentStatus) {
    if (currentStatus == 'new') return const SizedBox.shrink();

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

  // ---------------- Available Jobs ----------------
  Widget _availableJobsTab() {
    final query = FirebaseFirestore.instance
        .collection('jobs')
        .where('status', isEqualTo: 'new')
        .where('assignedDriverId', isNull: true)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No available jobs right now.'));
        }

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

                    if (!tender)
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: () => _acceptJob(doc.id),
                          child: const Text('Accept Job'),
                        ),
                      )
                    else
                      _TenderBidBox(
                        jobId: doc.id,
                        onSubmit: (price) => _submitBid(jobId: doc.id, price: price),
                        parsePrice: _parsePrice,
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

  // ---------------- My Jobs ----------------
  Widget _myJobsTab() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not signed in.'));
    }

    final query = FirebaseFirestore.instance
        .collection('jobs')
        .where('assignedDriverId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No jobs assigned to you yet.'));
        }

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

class _TenderBidBox extends StatefulWidget {
  final String jobId;
  final Future<void> Function(num price) onSubmit;
  final num? Function(String input) parsePrice;

  const _TenderBidBox({
    required this.jobId,
    required this.onSubmit,
    required this.parsePrice,
  });

  @override
  State<_TenderBidBox> createState() => _TenderBidBoxState();
}

class _TenderBidBoxState extends State<_TenderBidBox> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Text('Not signed in.');
    }

    final bidDocStream = FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.jobId)
        .collection('bids')
        .doc(user.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: bidDocStream,
      builder: (context, snap) {
        final hasBid = snap.data?.exists ?? false;
        final bidData = snap.data?.data();
        final bidPrice = bidData?['price'];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (hasBid && bidPrice != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Your bid: £${(bidPrice as num).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Your price (£)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                    final parsed = widget.parsePrice(_controller.text);
                    if (parsed == null || parsed <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a valid price')),
                      );
                      return;
                    }
                    setState(() => _busy = true);
                    try {
                      await widget.onSubmit(parsed);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: Text(hasBid ? 'Update Bid' : 'Submit Bid'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
