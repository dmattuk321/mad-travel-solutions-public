import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddJobPage extends StatefulWidget {
  const AddJobPage({super.key});

  @override
  State<AddJobPage> createState() => _AddJobPageState();
}

class _AddJobPageState extends State<AddJobPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _jobId = TextEditingController();
  final _pickupAddress = TextEditingController();
  final _dropoffAddress = TextEditingController();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _passengerCount = TextEditingController();
  final _luggage = TextEditingController();
  final _price = TextEditingController();
  final _flightDetails = TextEditingController();
  final _notes = TextEditingController();

  // Date + Time
  DateTime? _pickupDate;
  TimeOfDay? _pickupTime;

  bool _saving = false;

  @override
  void dispose() {
    _jobId.dispose();
    _pickupAddress.dispose();
    _dropoffAddress.dispose();
    _customerName.dispose();
    _customerPhone.dispose();
    _passengerCount.dispose();
    _luggage.dispose();
    _price.dispose();
    _flightDetails.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  String _formatTime(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  DateTime _combineDateTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _pickupDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _pickupTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _pickupTime = picked);
    }
  }

  Future<void> _saveJob() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pickupDate == null || _pickupTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select pickup date and time')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final pickupAt = _combineDateTime(_pickupDate!, _pickupTime!);

      final doc = await FirebaseFirestore.instance.collection('jobs').add({
        // Required job fields
        'jobId': _jobId.text.trim(),
        'pickupDate': _formatDate(_pickupDate!),
        'pickupTime': _formatTime(_pickupTime!),
        'pickupAt': Timestamp.fromDate(pickupAt), // helpful for ordering later
        'pickupAddress': _pickupAddress.text.trim(),
        'dropoffAddress': _dropoffAddress.text.trim(),
        'customerName': _customerName.text.trim(),
        'customerPhone': _customerPhone.text.trim(),
        'passengerCount': int.tryParse(_passengerCount.text.trim()) ?? 0,
        'luggage': _luggage.text.trim(),
        'price': double.tryParse(_price.text.trim()) ?? 0.0,
        'flightDetails': _flightDetails.text.trim(),
        'notes': _notes.text.trim(),

        // Assignment + status (IMPORTANT for queries)
        'status': 'new',
        'assignedDriverId': null,

        // Server timestamp
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Job created (${doc.id})')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating job: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
    _pickupDate == null ? 'Select date' : _formatDate(_pickupDate!);
    final timeText =
    _pickupTime == null ? 'Select time' : _formatTime(_pickupTime!);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Job')),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _jobId,
                  decoration:
                  const InputDecoration(labelText: 'Job ID (letters/numbers)'),
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickDate,
                        child: Text(dateText),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _pickTime,
                        child: Text(timeText),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                TextFormField(
                  controller: _pickupAddress,
                  decoration: const InputDecoration(labelText: 'Pickup Address'),
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _dropoffAddress,
                  decoration: const InputDecoration(labelText: 'Drop-off Address'),
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _customerName,
                  decoration: const InputDecoration(labelText: 'Customer Name'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _customerPhone,
                  decoration: const InputDecoration(labelText: 'Customer Number'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passengerCount,
                  decoration: const InputDecoration(labelText: 'Passenger Count'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _luggage,
                  decoration: const InputDecoration(labelText: 'Luggage Details'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _price,
                  decoration: const InputDecoration(labelText: 'Price'),
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _flightDetails,
                  decoration: const InputDecoration(labelText: 'Flight Details'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _notes,
                  decoration:
                  const InputDecoration(labelText: 'Other Details / Notes'),
                  maxLines: 3,
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saveJob,
                    child: _saving
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text('Create Job'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
