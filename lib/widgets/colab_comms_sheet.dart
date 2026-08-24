import 'package:flutter/material.dart';
import '../models/colab_models.dart';
import '../services/p2p_mesh_service.dart';

/// Modal bottom sheet providing 1-tap tactical pings and shared group waypoint management.
class ColabCommsSheet extends StatefulWidget {
  final double currentLat;
  final double currentLng;

  const ColabCommsSheet({
    super.key,
    required this.currentLat,
    required this.currentLng,
  });

  static Future<void> show(BuildContext context, {required double currentLat, required double currentLng}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => ColabCommsSheet(
        currentLat: currentLat,
        currentLng: currentLng,
      ),
    );
  }

  @override
  State<ColabCommsSheet> createState() => _ColabCommsSheetState();
}

class _ColabCommsSheetState extends State<ColabCommsSheet> {
  final TextEditingController _wptController = TextEditingController();
  bool _isAddingWpt = false;

  @override
  void dispose() {
    _wptController.dispose();
    super.dispose();
  }

  void _sendPing(PingType type) {
    P2pMeshService.instance.sendPing(type);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Broadcasted ping: ${MeshPing(id: '', type: type, senderId: '', senderName: '', senderColor: 0, timestamp: 0).title}'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _saveWaypoint() {
    final name = _wptController.text.trim();
    if (name.isEmpty) return;

    P2pMeshService.instance.addSharedWaypoint(
      name,
      widget.currentLat,
      widget.currentLng,
    );
    setState(() {
      _isAddingWpt = false;
      _wptController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Shared waypoint "$name" broadcasted to team!'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meshService = P2pMeshService.instance;
    final waypoints = meshService.sharedWaypoints;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.hub_outlined, color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TEAM COMMS & NAVSHARE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    Text(
                      'Encrypted zero-cloud tactical alerts',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 1-Tap Tactical Pings Section
          const Text(
            'TACTICAL 1-TAP PINGS',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPingChip(PingType.regroup),
              _buildPingChip(PingType.water),
              _buildPingChip(PingType.sprint),
              _buildPingChip(PingType.hazard),
              _buildPingChip(PingType.sos),
            ],
          ),
          const SizedBox(height: 24),

          // Shared Waypoints Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'SHARED WAYPOINTS (NAVSHARE)',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              if (!_isAddingWpt)
                TextButton.icon(
                  onPressed: () => setState(() => _isAddingWpt = true),
                  icon: const Icon(Icons.add_location_alt, size: 16, color: Color(0xFF10B981)),
                  label: const Text('Drop Pin', style: TextStyle(color: Color(0xFF10B981), fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_isAddingWpt) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _wptController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Summit View, Water Station, Regroup',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => setState(() => _isAddingWpt = false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _saveWaypoint,
                        icon: const Icon(Icons.share, size: 14),
                        label: const Text('Broadcast Pin', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (waypoints.isEmpty && !_isAddingWpt)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'No shared waypoints yet. Tap "Drop Pin" to drop a meeting point for your group.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            ...waypoints.map((wpt) => _buildWaypointTile(wpt)),
          ],
        ],
      ),
    );
  }

  Widget _buildPingChip(PingType type) {
    final sample = MeshPing(id: '', type: type, senderId: '', senderName: '', senderColor: 0, timestamp: 0);

    return InkWell(
      onTap: () => _sendPing(type),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sample.color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: sample.color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(sample.iconEmoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              sample.title,
              style: TextStyle(
                color: sample.color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaypointTile(SharedWaypoint wpt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF262626),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: wpt.color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.location_on, color: wpt.color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wpt.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Dropped by ${wpt.creatorName}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
            onPressed: () => P2pMeshService.instance.removeSharedWaypoint(wpt.id),
          ),
        ],
      ),
    );
  }
}
