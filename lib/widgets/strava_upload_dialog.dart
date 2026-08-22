import 'package:flutter/material.dart';
import '../services/strava_service.dart';
import '../services/export_service.dart';

/// Modal dialog providing 1-tap direct upload to Strava.
class StravaUploadDialog extends StatefulWidget {
  final int sessionId;
  final String activityName;
  final String activityType;

  const StravaUploadDialog({
    super.key,
    required this.sessionId,
    required this.activityName,
    required this.activityType,
  });

  @override
  State<StravaUploadDialog> createState() => _StravaUploadDialogState();
}

class _StravaUploadDialogState extends State<StravaUploadDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late String _selectedType;
  bool _isCommute = false;
  bool _isTrainer = false;
  bool _isUploading = false;
  String? _statusMessage;
  bool _uploadSuccess = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.activityName);
    _descController = TextEditingController(text: 'Recorded offline with TurnBack Endurance Tracker.');
    _selectedType = widget.activityType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _performUpload() async {
    setState(() {
      _isUploading = true;
      _statusMessage = 'Generating TCX telemetry package...';
    });

    try {
      // 1. Generate TCX payload for highest data fidelity (HR, Cadence, Elevation)
      final tcxString = await ExportService.instance.generateTcxString(
        widget.sessionId,
        _nameController.text.trim(),
      );

      final result = await StravaService.instance.uploadActivity(
        fileContent: tcxString,
        fileName: 'turnback_${widget.sessionId}.tcx',
        activityName: _nameController.text.trim(),
        activityType: _selectedType,
        description: _descController.text.trim(),
        isCommute: _isCommute,
        isTrainer: _isTrainer,
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadSuccess = result.success;
          _statusMessage = result.success
              ? (result.statusMessage ?? 'Uploaded to Strava successfully!')
              : (result.error ?? 'Upload failed.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadSuccess = false;
          _statusMessage = 'Upload error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFC4C02), // Strava Orange
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.cloud_upload, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Strava Direct Upload',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_uploadSuccess) ...[
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        _statusMessage ?? 'Activity Uploaded!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your track, pace, and metrics are synced to Strava.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Activity Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: ['run', 'ride', 'walk', 'hike'].contains(_selectedType.toLowerCase())
                      ? _selectedType.toLowerCase()
                      : 'run',
                  decoration: const InputDecoration(
                    labelText: 'Sport Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'run', child: Text('Run')),
                    DropdownMenuItem(value: 'ride', child: Text('Ride / Cycling')),
                    DropdownMenuItem(value: 'walk', child: Text('Walk')),
                    DropdownMenuItem(value: 'hike', child: Text('Hike / Trek')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedType = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Commute', style: TextStyle(fontSize: 12)),
                        value: _isCommute,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setState(() => _isCommute = v ?? false),
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Trainer', style: TextStyle(fontSize: 12)),
                        value: _isTrainer,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setState(() => _isTrainer = v ?? false),
                      ),
                    ),
                  ],
                ),
                if (_statusMessage != null && !_uploadSuccess)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isUploading ? null : _performUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFC4C02),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isUploading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                              SizedBox(width: 10),
                              Text('Uploading to Strava...'),
                            ],
                          )
                        : const Text('1-Tap Upload to Strava', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
