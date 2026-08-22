import 'package:flutter/material.dart';
import '../models/teammate.dart';
import '../services/p2p_mesh_service.dart';
import 'mesh_qr_widget.dart';

/// Compact HUD badge & expandable bottom sheet showing live P2P mesh teammates.
class MeshRadarHudWidget extends StatelessWidget {
  const MeshRadarHudWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: P2pMeshService.instance,
      builder: (context, _) {
        final mesh = P2pMeshService.instance;
        if (!mesh.isMeshActive) {
          return const SizedBox.shrink();
        }

        final activeTeammates = mesh.teammates.where((t) => t.isActive).toList();
        final count = activeTeammates.length;

        return Positioned(
          top: 100,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Mesh Status Pill Button
              GestureDetector(
                onTap: () => _showMeshTeammatesSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: count > 0 ? Colors.green : Colors.amber,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: count > 0 ? Colors.greenAccent : Colors.amberAccent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        count > 0 ? '$count Active Teammate${count > 1 ? 's' : ''}' : 'Mesh Ready (0 Peers)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.group, size: 14, color: Colors.white70),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Live Teammate Status Chips
              ...activeTeammates.take(3).map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.color.withOpacity(0.8), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 5,
                        backgroundColor: t.color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t.displayTag,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              )),
            ],
          ),
        );
      },
    );
  }

  void _showMeshTeammatesSheet(BuildContext context) {
    final mesh = P2pMeshService.instance;
    final config = mesh.activeConfig;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return AnimatedBuilder(
          animation: mesh,
          builder: (ctx, _) {
            final teammates = mesh.teammates;

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            config?.sessionName ?? 'Group Mesh Session',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'P2P E2EE Tunnel • ${teammates.length} Connected',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                      if (config != null)
                        IconButton.filledTonal(
                          icon: const Icon(Icons.qr_code, size: 20),
                          tooltip: 'Show Relay QR Code',
                          onPressed: () {
                            Navigator.pop(ctx);
                            showDialog(
                              context: context,
                              builder: (dCtx) => MeshQrDisplayDialog(config: config),
                            );
                          },
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  if (teammates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No teammates detected yet.\nShare the QR code or link to bring riders in!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ...teammates.map((t) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: t.color,
                        child: Text(
                          t.username.isNotEmpty ? t.username[0].toUpperCase() : 'R',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(t.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${t.formattedDistance} away • ${t.speedKmh.toStringAsFixed(1)} km/h • ${t.altitude.toStringAsFixed(0)}m elev',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: t.isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          t.isActive ? 'Active' : 'Offline',
                          style: TextStyle(
                            color: t.isActive ? Colors.green : Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share, size: 16),
                      label: const Text('Invite / Relay QR Code to Another Rider'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        if (config != null) {
                          showDialog(
                            context: context,
                            builder: (dCtx) => MeshQrDisplayDialog(config: config),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
