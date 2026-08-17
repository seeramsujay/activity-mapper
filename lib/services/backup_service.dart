import 'dart:io';
import 'export_service.dart';

/// Service responsible for compiling local application backups.
///
/// Compresses the active SQLite database files (including WAL transaction logs)
/// and exported session logs across all formats into a unified, versioned ZIP archive.
class BackupService {
  /// The singleton instance of [BackupService].
  static final BackupService instance = BackupService._init();

  BackupService._init();

  /// Compiles a complete ZIP backup of all local application files and databases.
  Future<File> createZipBackup() async {
    return await ExportService.instance.exportLifetimeZipBackup();
  }
}
