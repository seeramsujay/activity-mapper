import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Represents a public reflexive network endpoint (IP + Port) discovered via STUN.
class StunEndpoint {
  final String ip;
  final int port;

  const StunEndpoint({required this.ip, required this.port});

  @override
  String toString() => '$ip:$port';
}

/// Lightweight, zero-dependency RFC 5389 STUN client for UDP NAT traversal.
///
/// Discovers public reflexive IPv4 address and mapped port behind Carrier-Grade NAT (CGNAT)
/// using Google's free public STUN servers.
class StunService {
  static const String primaryStunServer = 'stun.l.google.com';
  static const String fallbackStunServer = 'stun1.l.google.com';
  static const int stunDefaultPort = 19302;
  static const int magicCookie = 0x2112A442;

  /// Resolves the public IP and UDP port for a given local socket.
  ///
  /// If [localSocket] is provided, performs STUN discovery directly on that socket
  /// so that the exact NAT port mapping remains open and valid for hole punching.
  static Future<StunEndpoint?> discoverPublicEndpoint({
    RawDatagramSocket? localSocket,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    // Try primary server, fallback to secondary
    final endpoint = await _queryServer(primaryStunServer, localSocket, timeout);
    if (endpoint != null) return endpoint;
    return await _queryServer(fallbackStunServer, localSocket, timeout);
  }

  static Future<StunEndpoint?> _queryServer(
    String serverHostname,
    RawDatagramSocket? boundSocket,
    Duration timeout,
  ) async {
    RawDatagramSocket? socket;
    bool shouldCloseSocket = false;

    try {
      if (boundSocket != null) {
        socket = boundSocket;
      } else {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        shouldCloseSocket = true;
      }

      final addresses = await InternetAddress.lookup(serverHostname, type: InternetAddressType.IPv4);
      if (addresses.isEmpty) return null;
      final serverAddress = addresses.first;

      // 1. Build RFC 5389 Binding Request (20 bytes header)
      final requestBytes = _buildBindingRequest();
      final transactionId = requestBytes.sublist(8, 20);

      final completer = Completer<StunEndpoint?>();

      late final StreamSubscription sub;
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null && datagram.data.length >= 20) {
            final parsed = _parseBindingResponse(datagram.data, transactionId);
            if (parsed != null && !completer.isCompleted) {
              completer.complete(parsed);
            }
          }
        }
      });

      // Send binding request to STUN server
      socket.send(requestBytes, serverAddress, stunDefaultPort);

      // Wait with timeout
      final result = await completer.future.timeout(timeout, onTimeout: () => null);
      await sub.cancel();
      return result;
    } catch (e) {
      debugPrint('STUN discovery error on $serverHostname: $e');
      return null;
    } finally {
      if (shouldCloseSocket) {
        try {
          socket?.close();
        } catch (_) {}
      }
    }
  }

  /// Builds a 20-byte RFC 5389 Binding Request packet.
  static Uint8List _buildBindingRequest() {
    final buffer = ByteData(20);
    // Message Type: 0x0001 (Binding Request)
    buffer.setUint16(0, 0x0001, Endian.big);
    // Message Length: 0x0000 (No attributes in request)
    buffer.setUint16(2, 0x0000, Endian.big);
    // Magic Cookie: 0x2112A442
    buffer.setUint32(4, magicCookie, Endian.big);

    // 12-byte Transaction ID (random cryptographically strong values)
    final rng = Random();
    for (int i = 8; i < 20; i++) {
      buffer.setUint8(i, rng.nextInt(256));
    }

    return buffer.buffer.asUint8List();
  }

  /// Parses a STUN Binding Response and extracts XOR-MAPPED-ADDRESS or MAPPED-ADDRESS.
  static StunEndpoint? _parseBindingResponse(Uint8List data, List<int> expectedTransactionId) {
    if (data.length < 20) return null;
    final byteData = ByteData.sublistView(data);

    final msgType = byteData.getUint16(0, Endian.big);
    // 0x0101 = Binding Success Response
    if (msgType != 0x0101) return null;

    final cookie = byteData.getUint32(4, Endian.big);
    if (cookie != magicCookie) return null;

    // Verify transaction ID
    for (int i = 0; i < 12; i++) {
      if (data[8 + i] != expectedTransactionId[i]) return null;
    }

    final msgLength = byteData.getUint16(2, Endian.big);
    int offset = 20;
    final totalLen = min(data.length, 20 + msgLength);

    while (offset + 4 <= totalLen) {
      final attrType = byteData.getUint16(offset, Endian.big);
      final attrLen = byteData.getUint16(offset + 2, Endian.big);
      offset += 4;

      if (offset + attrLen > data.length) break;

      // XOR-MAPPED-ADDRESS (0x0020)
      if (attrType == 0x0020 && attrLen >= 8) {
        final family = byteData.getUint8(offset + 1);
        if (family == 0x01) {
          // IPv4
          final rawPort = byteData.getUint16(offset + 2, Endian.big);
          final xorPort = rawPort ^ (magicCookie >> 16);

          final xorIp = byteData.getUint32(offset + 4, Endian.big);
          final realIpVal = xorIp ^ magicCookie;

          final ipStr = '${(realIpVal >> 24) & 0xFF}.${(realIpVal >> 16) & 0xFF}.${(realIpVal >> 8) & 0xFF}.${realIpVal & 0xFF}';
          return StunEndpoint(ip: ipStr, port: xorPort);
        }
      }

      // MAPPED-ADDRESS (0x0001) - Fallback for older STUN implementations
      if (attrType == 0x0001 && attrLen >= 8) {
        final family = byteData.getUint8(offset + 1);
        if (family == 0x01) {
          // IPv4
          final port = byteData.getUint16(offset + 2, Endian.big);
          final ipVal = byteData.getUint32(offset + 4, Endian.big);
          final ipStr = '${(ipVal >> 24) & 0xFF}.${(ipVal >> 16) & 0xFF}.${(ipVal >> 8) & 0xFF}.${ipVal & 0xFF}';
          return StunEndpoint(ip: ipStr, port: port);
        }
      }

      // Attributes are padded to multiples of 4 bytes
      offset += (attrLen + 3) & ~3;
    }

    return null;
  }
}
