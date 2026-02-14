import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DispatcherHome extends StatefulWidget {
  final bool isAdmin;
  const DispatcherHome({super.key, this.isAdmin = false});

  @override
  State<DispatcherHome> createState() => _DispatcherHomeState();
}

class _DispatcherHomeState extends State<DispatcherHome>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _jobsRef = FirebaseFirestore.instance.collection('jobs');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _jobsStream() {
    return _jobsRef
        .orderBy('createdAt', descending: true)
        .limit(200)
        .withConverter<Map<String, dynamic>>(
      fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
      toFirestore: (data, _) => data,
    )
        .snapshots();
  }

  String _s(dynamic v) => (v ?? '').toString();
  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  bool _isNewUnassigned(Map<String, dynamic> j) {
    return _s(j['status']) == 'new' && j['assignedDriverId'] == null;
  }

  bool _isTender(Map<String, dynamic> j) => _s(j['pricingType']) == 'tender';

  bool _isAssigned(Map<String, dynamic> j) {
    return j['assignedDriverId'] != null && _s(j['assignedDriverId']).trim().isNotEmpty;
  }

  bool _isAwardPending(Map<String, dynamic> j) => _s(j['status']) == 'award_pending';
  bool _isDeclined(Map<String, dynamic> j) => _s(j['status']) == 'declined';

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
            Tab(text: 'Accepted / Pending'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _jobsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _center('Error: ${snapshot.error}');
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;

          final newJobs = docs.where((d) => _isNewUnassigned(d.data())).toList();

          final tenderJobs = docs
              .where((d) => _isNewUnassigned(d.data()) && _isTender(d.data()))
              .toList();

          final acceptedOrPending = docs
              .where((d) => _isAssigned(d.data()) || _isAwardPending(d.data()) || _isDeclined(d.data()))
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _jobsList(
                jobs: newJobs,
                emptyText: 'No new jobs.',
                onTap: (doc) => _openJobDetails(doc),
              ),
              _jobsList(
                jobs: tenderJobs,
                emptyText: 'No tender jobs.',
                onTap: (doc) => _openTenderBids(doc),
              ),
              _jobsList(
                jobs: acceptedOrPending,
                emptyText: 'No accepted / pending jobs yet.',
                onTap: (doc) => _openJobDetails(doc),
                showDriverChip: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _center(String t) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(t, textAlign: TextAlign.center),
    ),
  );

  Widget _jobsList({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> jobs,
    required String emptyText,
    required void Function(QueryDocumentSnapshot<Map<String, dynamic>>) onTap,
    bool showDriverChip = false,
  }) {
    if (jobs.isEmpty) return _center(emptyText);

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final doc = jobs[i];
        final j = doc.data();

        final pickup = _s(j['pickupAddress']);
        final dropoff = _s(j['dropoffAddress']);
        final status = _s(j['status']);
        final pricingType = _s(j['pricingType']);
        final price = _d(j['price']);

        final assignedDriverId = _s(j['assignedDriverId']);
        final assignedDriverName = _s(j['assignedDriverName']);

        return Card(
          elevation: 2,
          child: ListTile(
            onTap: () => onTap(doc),
            title: Text(
              pickup.isEmpty ? '(no pickup)' : pickup,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  dropoff.isEmpty ? '(no dropoff)' : dropoff,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _chip('status: $status'),
                    _chip('type: $pricingType'),
                    if (pricingType == 'fixed') _chip('£${price.toStringAsFixed(2)}'),
                    if (showDriverChip && assignedDriverId.isNotEmpty)
                      _chip('driver: ${assignedDriverName.isNotEmpty ? assignedDriverName : assignedDriverId}'),
                  ],
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  void _openJobDetails(QueryDocumentSnapshot<Map<String, dynamic>> jobDoc) {
    final j = jobDoc.data();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Job ${jobDoc.id}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _kv('Status', _s(j['status'])),
                _kv('Pricing type', _s(j['pricingType'])),
                _kv('Pickup', _s(j['pickupAddress'])),
                _kv('Dropoff', _s(j['dropoffAddress'])),
                _kv('Pickup date', _s(j['pickupDate'])),
                _kv('Pickup time', _s(j['pickupTime'])),
                if (_s(j['pricingType']) == 'fixed')
                  _kv('Price', '£${_d(j['price']).toStringAsFixed(2)}'),
                if (_s(j['pricingType']) == 'tender' && _s(j['awardedBidPrice']).isNotEmpty)
                  _kv('Awarded bid', '£${_d(j['awardedBidPrice']).toStringAsFixed(2)}'),
                _kv('Driver', _s(j['assignedDriverName']).isNotEmpty ? _s(j['assignedDriverName']) : _s(j['assignedDriverId'])),
                const SizedBox(height: 16),
                if (_isTender(j))
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openTenderBids(jobDoc);
                    },
                    icon: const Icon(Icons.gavel),
                    label: const Text('View bids'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(v.isEmpty ? '-' : v)),
        ],
      ),
    );
  }

  void _openTenderBids(QueryDocumentSnapshot<Map<String, dynamic>> jobDoc) {
    final bidsRef = jobDoc.reference.collection('bids');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tender Bids',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('Job: ${jobDoc.id}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: bidsRef
                        .orderBy('price')
                        .withConverter<Map<String, dynamic>>(
                      fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
                      toFirestore: (data, _) => data,
                    )
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) return _center('Error loading bids: ${snap.error}');
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                      final bidDocs = snap.data!.docs;
                      if (bidDocs.isEmpty) return _center('No bids yet.');

                      return ListView.separated(
                        itemCount: bidDocs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final bidDoc = bidDocs[i];
                          final b = bidDoc.data();

                          final driverUid = _s(b['driverId']).isNotEmpty ? _s(b['driverId']) : bidDoc.id;
                          final price = _d(b['price']);

                          return ListTile(
                            title: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              future: FirebaseFirestore.instance.collection('users').doc(driverUid).get(),
                              builder: (context, userSnap) {
                                if (userSnap.hasData && userSnap.data!.exists) {
                                  final u = userSnap.data!.data() as Map<String, dynamic>?;
                                  final name = (u?['name'] ?? '').toString();
                                  final email = (u?['email'] ?? '').toString();
                                  final display = name.isNotEmpty ? name : (email.isNotEmpty ? email : driverUid);
                                  return Text(display, maxLines: 1, overflow: TextOverflow.ellipsis);
                                }
                                return Text(driverUid, maxLines: 1, overflow: TextOverflow.ellipsis);
                              },
                            ),
                            subtitle: Text('£${price.toStringAsFixed(2)}  •  $driverUid'),
                            trailing: ElevatedButton(
                              onPressed: () => _awardTenderWithTimeLimit(
                                jobDoc: jobDoc,
                                driverUid: driverUid,
                                bidPrice: price,
                              ),
                              child: const Text('Offer'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<int?> _promptMinutes() async {
    final controller = TextEditingController(text: '30');

    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Time limit (minutes)'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'e.g. 30',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final minutes = int.tryParse(controller.text.trim());
              Navigator.pop(context, (minutes != null && minutes > 0) ? minutes : null);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _awardTenderWithTimeLimit({
    required QueryDocumentSnapshot<Map<String, dynamic>> jobDoc,
    required String driverUid,
    required double bidPrice,
  }) async {
    final minutes = await _promptMinutes();
    if (minutes == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(driverUid).get();
      final u = userDoc.data() as Map<String, dynamic>?;
      final driverName = (u?['name'] ?? u?['email'] ?? driverUid).toString();

      final expiresAt = Timestamp.fromDate(DateTime.now().add(Duration(minutes: minutes)));

      await jobDoc.reference.update({
        'assignedDriverId': driverUid,
        'assignedDriverName': driverName,
        'status': 'award_pending',
        'awardMinutes': minutes,
        'awardExpiresAt': expiresAt,
        'awardedBidPrice': bidPrice,
        'awardedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context); // close bids sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Offered to $driverName ($minutes mins)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to offer: $e')),
        );
      }
    }
  }
}
