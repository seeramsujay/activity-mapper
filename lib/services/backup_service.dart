import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Service responsible for compiling local application backups.
///
/// Compresses the active SQLite database files (including WAL transaction logs)
/// and exported GPX logs into a unified, versioned ZIP archive.
class BackupService {
  /// The singleton instance of [BackupService].
  static final BackupService instance = BackupService._init();

  BackupService._init();

  /// Compiles a ZIP backup of all local application files.
  ///
  /// Gathers `turnback.db`, `turnback.db-wal`, `turnback.db-shm` and all `.gpx` files from
  /// the documents directory. Returns the completed [File] pointing to the compressed archive.
  Future<File> createZipBackup() async {
    final archive = Archive();

    // 1. Resolve SQLite DB Path
    String dbPath;
    if (Platform.isAndroid) {
      dbPath = join(await getDatabasesPath(), 'turnback.db');
    } else {
      final dbFolder = await getApplicationDocumentsDirectory();
      dbPath = join(dbFolder.path, 'turnback.db');
    }

    // 2. Add SQLite database file
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('turnback.db', dbBytes.length, dbBytes));
      
      // Preserve active transactions by checking for Write-Ahead Logs
      final walFile = File('$dbPath-wal');
      if (await walFile.exists()) {
        final walBytes = await walFile.readAsBytes();
        archive.addFile(ArchiveFile('turnback.db-wal', walBytes.length, walBytes));
      }
      
      final shmFile = File('$dbPath-shm');
      if (await shmFile.exists()) {
        final shmBytes = await shmFile.readAsBytes();
        archive.addFile(ArchiveFile('turnback.db-shm', shmBytes.length, shmBytes));
      }
    }

    // 3. Scan and collect all GPX files from Documents directory
    final docDir = await getApplicationDocumentsDirectory();
    final List<FileSystemEntity> files = docDir.listSync();
    
    for (final file in files) {
      if (file is File && extension(file.path) == '.gpx') {
        final bytes = await file.readAsBytes();
        final name = basename(file.path);
        archive.addFile(ArchiveFile('gpx_logs/$name', bytes.length, bytes));
      }
    }

    // 4. Compress to single ZIP container
    final zipData = ZipEncoder().encode(archive);
    if (zipData == null) {
      throw Exception("ZIP compression failed.");
    }

    final backupFile = File(join(
      docDir.path,
      'turnback_backup_${DateTime.now().millisecondsSinceEpoch}.zip',
    ));

    return await backupFile.writeAsBytes(zipData, flush: true);
  }
}

