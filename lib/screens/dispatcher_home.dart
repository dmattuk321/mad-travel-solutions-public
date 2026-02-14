import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DispatcherHome extends StatefulWidget {
  final bool isAdmin; // you pass this from AdminHome
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

  // We use a single simple query to avoid composite-index pain:
  // Firestore single-field index on createdAt works by default.
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

  // Helpers
  String _s(dynamic v) => (v ?? '').toString();
  double _d(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  bool _isNewUnassigned(Map<String, dynamic> j) {
    return _s(j['status']) == 'new' && j['assignedDriverId'] == null;
  }

  bool _isTender(Map<String, dynamic> j) {
    return _s(j['pricingType']) == 'tender';
  }

  bool _isFixed(Map<String, dynamic> j) {
    return _s(j['pricingType']) == 'fixed';
  }

  bool _isAssigned(Map<String, dynamic> j) {
    return j['assignedDriverId'] != null &&
        _s(j['assignedDriverId']).trim().isNotEmpty;
  }

  // UI
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
            Tab(text: 'Accepted Jobs'),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _jobsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _centerText('Error: ${snapshot.error}');
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          // Split into tabs by filtering locally (avoids composite index requirements)
          final newJobs = docs
              .where((d) => _isNewUnassigned(d.data()))
              .toList(growable: false);

          final tenderJobs = docs
              .where((d) => _isNewUnassigned(d.data()) && _isTender(d.data()))
              .toList(growable: false);

          final acceptedJobs = docs
              .where((d) => _isAssigned(d.data()))
              .toList(growable: false);

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
                jobs: acceptedJobs,
                emptyText: 'No accepted/assigned jobs yet.',
                onTap: (doc) => _openJobDetails(doc),
                showDriverChip: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _centerText(String t) => Center(
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
    if (jobs.isEmpty) return _centerText(emptyText);

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
                      _chip(
                        'driver: ${assignedDriverName.isNotEmpty ? assignedDriverName : assignedDriverId}',
                      ),
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

  // ---------- DETAILS ----------
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
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _kv('Status', _s(j['status'])),
                _kv('Pricing type', _s(j['pricingType'])),
                _kv('Pickup', _s(j['pickupAddress'])),
                _kv('Dropoff', _s(j['dropoffAddress'])),
                _kv('Pickup date', _s(j['pickupDate'])),
                _kv('Pickup time', _s(j['pickupTime'])),
                if (_s(j['pricingType']) == 'fixed')
                  _kv('Price', '£${_d(j['price']).toStringAsFixed(2)}'),
                _kv('Passengers', _s(j['passengerCount'])),
                _kv('Flight', _s(j['flightDetails'])),
                _kv('Notes', _s(j['notes'])),
                const SizedBox(height: 16),
                if (_isTender(j)) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openTenderBids(jobDoc);
                    },
                    icon: const Icon(Icons.gavel),
                    label: const Text('View bids'),
                  ),
                ],
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
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(v.isEmpty ? '-' : v)),
        ],
      ),
    );
  }

  // ---------- TENDER: VIEW BIDS + ACCEPT ----------
  void _openTenderBids(QueryDocumentSnapshot<Map<String, dynamic>> jobDoc) {
    final bidsRef = jobDoc.reference.collection('bids');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tender Bids',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Job: ${jobDoc.id}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
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
                      if (snap.hasError) {
                        return _centerText('Error loading bids: ${snap.error}');
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final bidDocs = snap.data!.docs;
                      if (bidDocs.isEmpty) {
                        return _centerText('No bids yet.');
                      }

                      return ListView.separated(
                        itemCount: bidDocs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final bidDoc = bidDocs[i];
                          final b = bidDoc.data();

                          // IMPORTANT:
                          // Your rule structure means bidDoc.id is the driver uid
                          final driverUid = _s(b['driverId']).isNotEmpty
                              ? _s(b['driverId'])
                              : bidDoc.id;

                          final price = _d(b['price']);
                          final cachedName = _s(b['driverName']);
                          final cachedEmail = _s(b['driverEmail']);

                          return ListTile(
                            title: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(driverUid)
                                  .withConverter<Map<String, dynamic>>(
                                fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
                                toFirestore: (data, _) => data,
                              )
                                  .get(),
                              builder: (context, userSnap) {
                                String display = '';

                                if (cachedName.isNotEmpty) display = cachedName;
                                else if (cachedEmail.isNotEmpty) display = cachedEmail;

                                if (display.isEmpty && userSnap.hasData && userSnap.data!.exists) {
                                  final u = userSnap.data!.data() ?? {};
                                  final name = _s(u['name']);
                                  final email = _s(u['email']);
                                  display = name.isNotEmpty ? name : (email.isNotEmpty ? email : '');
                                }

                                if (display.isEmpty) display = driverUid;

                                return Text(display, maxLines: 1, overflow: TextOverflow.ellipsis);
                              },
                            ),
                            subtitle: Text('Driver UID: $driverUid'),
                            trailing: Wrap(
                              spacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('£${price.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                ElevatedButton(
                                  onPressed: () => _acceptTenderBid(
                                    jobDoc: jobDoc,
                                    driverUid: driverUid,
                                    bidPrice: price,
                                  ),
                                  child: const Text('Accept'),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _acceptTenderBid({
    required QueryDocumentSnapshot<Map<String, dynamic>> jobDoc,
    required String driverUid,
    required double bidPrice,
  }) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(driverUid).get();
      final u = userDoc.data() as Map<String, dynamic>?;
      final driverName = (u?['name'] ?? u?['email'] ?? driverUid).toString();

      await jobDoc.reference.update({
        'assignedDriverId': driverUid,
        'assignedDriverName': driverName,
        'status': 'accepted',
        // If you want tender to become a fixed agreed price:
        'price': bidPrice,
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context); // close bids sheet
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accepted bid (£${bidPrice.toStringAsFixed(2)}) for $driverName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept bid: $e')),
        );
      }
    }
  }
}
