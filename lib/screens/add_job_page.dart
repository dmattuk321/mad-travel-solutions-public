import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddJobPage extends StatefulWidget {
  final bool isAdmin;
  const AddJobPage({super.key, this.isAdmin = false});

  @override
  State<AddJobPage> createState() => _AddJobPageState();
}

class _AddJobPageState extends State<AddJobPage> {
  final _formKey = GlobalKey<FormState>();

  // Core fields
  final _pickupAddressCtrl = TextEditingController();
  final _dropoffAddressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _passengerCountCtrl = TextEditingController();
  final _flightDetailsCtrl = TextEditingController();

  // Pickup date/time stored as strings (matching your existing job format)
  final _pickupDateCtrl = TextEditingController();
  final _pickupTimeCtrl = TextEditingController();

  // Price (only required for fixed)
  final _priceCtrl = TextEditingController();

  String _pricingType = 'fixed'; // fixed | tender
  bool _saving = false;

  @override
  void dispose() {
    _pickupAddressCtrl.dispose();
    _dropoffAddressCtrl.dispose();
    _notesCtrl.dispose();
    _passengerCountCtrl.dispose();
    _flightDetailsCtrl.dispose();
    _pickupDateCtrl.dispose();
    _pickupTimeCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  num? _parseMoney(String input) {
    final cleaned = input.replaceAll('£', '').trim();
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );

    if (picked == null) return;

    // Store as dd/MM/yyyy (simple UK style)
    final dd = picked.day.toString().padLeft(2, '0');
    final mm = picked.month.toString().padLeft(2, '0');
    final yyyy = picked.year.toString();
    _pickupDateCtrl.text = '$dd/$mm/$yyyy';
    setState(() {});
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: now,
    );

    if (picked == null) return;

    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    _pickupTimeCtrl.text = '$hh:$mm';
    setState(() {});
  }

  Future<void> _saveJob() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are not signed in.')),
      );
      return;
    }

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    setState(() => _saving = true);

    try {
      final jobs = FirebaseFirestore.instance.collection('jobs');
      final docRef = jobs.doc(); // create ID first so we can store it as jobId

      final pickupAddress = _s(_pickupAddressCtrl.text);
      final dropoffAddress = _s(_dropoffAddressCtrl.text);
      final pickupDate = _s(_pickupDateCtrl.text);
      final pickupTime = _s(_pickupTimeCtrl.text);
      final notes = _s(_notesCtrl.text);
      final pax = _s(_passengerCountCtrl.text);
      final flight = _s(_flightDetailsCtrl.text);

      num? price;
      if (_pricingType == 'fixed') {
        price = _parseMoney(_priceCtrl.text);
      } else {
        price = null; // tender: driver bids, dispatcher awards and sets price later
      }

      await docRef.set({
        'jobId': docRef.id,

        'status': 'new',
        'pricingType': _pricingType, // "fixed" | "tender"

        'pickupAddress': pickupAddress,
        'dropoffAddress': dropoffAddress,
        'pickupDate': pickupDate,
        'pickupTime': pickupTime,

        // optional details
        if (notes.isNotEmpty) 'notes': notes,
        if (pax.isNotEmpty) 'passengerCount': pax,
        if (flight.isNotEmpty) 'flightDetails': flight,

        // price only for fixed jobs
        'price': price,

        // assignment fields
        'assignedDriverId': null,
        'assignedDriverName': null,

        // auditing
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'createdByEmail': user.email ?? '',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pricingType == 'fixed'
                ? 'Fixed job created'
                : 'Tender job created (drivers can bid)',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isAdmin ? 'Add Job (Admin)' : 'Add Job';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Pricing type selector
              Row(
                children: [
                  const Text(
                    'Pricing:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _pricingType,
                    items: const [
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed price')),
                      DropdownMenuItem(value: 'tender', child: Text('Tender (drivers bid)')),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                      if (v == null) return;
                      setState(() {
                        _pricingType = v;
                        if (_pricingType == 'tender') {
                          _priceCtrl.clear();
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _pickupAddressCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Pickup address',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (_s(v).isEmpty) return 'Pickup address is required';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _dropoffAddressCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Drop-off address',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (_s(v).isEmpty) return 'Drop-off address is required';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Date / Time pickers
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pickupDateCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Pickup date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: _saving ? null : _pickDate,
                      validator: (v) {
                        if (_s(v).isEmpty) return 'Pickup date is required';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _pickupTimeCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Pickup time',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time),
                      ),
                      onTap: _saving ? null : _pickTime,
                      validator: (v) {
                        if (_s(v).isEmpty) return 'Pickup time is required';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Price only for fixed
              if (_pricingType == 'fixed') ...[
                TextFormField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price (£)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 35 or 35.00',
                  ),
                  validator: (v) {
                    final n = _parseMoney(_s(v));
                    if (n == null || n <= 0) return 'Enter a valid price';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Tender job: drivers will submit their own price.\n'
                        'You will award it from the Tender Jobs tab.',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Optional extras
              TextFormField(
                controller: _passengerCountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Passengers (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _flightDetailsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Flight details (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _notesCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),

              ElevatedButton.icon(
                onPressed: _saving ? null : _saveJob,
                icon: _saving
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.save),
                label: Text(_saving ? 'Saving…' : 'Create Job'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}