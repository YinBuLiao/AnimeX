import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:animex_mobile/data/dtos/download_entry.dart';

const _storeKey = 'animex.downloads.v1';

class DownloadManager extends ChangeNotifier {
  final FileDownloader _dl;
  final SharedPreferences _prefs;
  final String _appDocsDir;
  final Map<String, DownloadEntry> _entries = {};
  StreamSubscription<TaskUpdate>? _sub;
  bool _started = false;

  DownloadManager._(this._dl, this._prefs, this._appDocsDir);

  /// Singleton bootstrap. Reads persisted entries, attaches to the
  /// background_downloader update stream and starts the platform service.
  static Future<DownloadManager> create({
    FileDownloader? downloader,
    SharedPreferences? prefs,
    Directory? appDocsDir,
  }) async {
    final dl = downloader ?? FileDownloader();
    final sp = prefs ?? await SharedPreferences.getInstance();
    final dir = appDocsDir ?? await getApplicationDocumentsDirectory();
    final m = DownloadManager._(dl, sp, dir.path);
    m._loadFromPrefs();
    await m._start();
    return m;
  }

  /// Visible for tests — same as [create] but synchronous and skips real
  /// downloader startup (callers wire a fake [downloader]).
  @visibleForTesting
  factory DownloadManager.forTest({
    required FileDownloader downloader,
    required SharedPreferences prefs,
    required String appDocsDir,
  }) {
    final m = DownloadManager._(downloader, prefs, appDocsDir);
    m._loadFromPrefs();
    return m;
  }

  List<DownloadEntry> get entries {
    final list = _entries.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  DownloadEntry? entryFor(String fileId) => _entries[fileId];

  bool isComplete(String fileId) => _entries[fileId]?.isComplete == true;

  Future<DownloadEntry> enqueue({
    required String fileId,
    required String url,
    required String bangumiTitle,
    String? episode,
    required String fileName,
    String? coverUrl,
    Map<String, String> headers = const {},
  }) async {
    final cleanBangumi = sanitizeFilename(bangumiTitle);
    final cleanFile = sanitizeFilename(fileName);
    final localPath = '$_appDocsDir/AnimeX/$cleanBangumi/$cleanFile';

    final entry = DownloadEntry(
      fileId: fileId,
      bangumiTitle: bangumiTitle,
      episode: episode,
      fileName: cleanFile,
      coverUrl: coverUrl,
      url: url,
      localPath: localPath,
      status: DownloadStatus.queued,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    _entries[fileId] = entry;
    await _persist();
    notifyListeners();

    final task = DownloadTask(
      taskId: fileId,
      url: url,
      filename: cleanFile,
      baseDirectory: BaseDirectory.applicationDocuments,
      directory: 'AnimeX/$cleanBangumi',
      headers: headers,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 3,
    );
    await _dl.enqueue(task);
    return entry;
  }

  Future<void> cancel(String fileId) async {
    await _dl.cancelTaskWithId(fileId);
    final e = _entries[fileId];
    if (e != null) {
      _entries[fileId] = e.copyWith(
        status: DownloadStatus.canceled,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      await _persist();
      notifyListeners();
    }
  }

  Future<void> pause(String fileId) async {
    final task = await _dl.taskForId(fileId);
    if (task != null) await _dl.pause(task as DownloadTask);
  }

  Future<void> resume(String fileId) async {
    final task = await _dl.taskForId(fileId);
    if (task != null) await _dl.resume(task as DownloadTask);
  }

  Future<void> deleteEntry(String fileId) async {
    await _dl.cancelTaskWithId(fileId);
    final e = _entries.remove(fileId);
    if (e != null) {
      try {
        final f = File(e.localPath);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Best-effort: ignore filesystem errors.
      }
    }
    await _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    _sub = _dl.updates.listen(_onUpdate);
    // background_downloader needs to know to track our previously-known
    // tasks across restarts so the OS can resume them.
    final known = _entries.values
        .where((e) => e.status == DownloadStatus.running ||
            e.status == DownloadStatus.queued ||
            e.status == DownloadStatus.paused)
        .toList();
    if (known.isNotEmpty) {
      try {
        await _dl.start();
      } catch (_) {/* idempotent */}
    }
  }

  /// Visible for tests.
  @visibleForTesting
  void handleUpdate(TaskUpdate update) => _onUpdate(update);

  void _onUpdate(TaskUpdate u) {
    final id = u.task.taskId;
    final current = _entries[id];
    if (current == null) return;
    DownloadEntry next = current;
    if (u is TaskStatusUpdate) {
      switch (u.status) {
        case TaskStatus.enqueued:
          next = next.copyWith(status: DownloadStatus.queued);
        case TaskStatus.running:
          next = next.copyWith(status: DownloadStatus.running);
        case TaskStatus.paused:
          next = next.copyWith(status: DownloadStatus.paused);
        case TaskStatus.complete:
          next = next.copyWith(
            status: DownloadStatus.complete,
            downloadedBytes: next.totalBytes > 0
                ? next.totalBytes
                : next.downloadedBytes,
          );
        case TaskStatus.failed:
        case TaskStatus.notFound:
          next = next.copyWith(
            status: DownloadStatus.failed,
            errorMessage: u.exception?.description,
          );
        case TaskStatus.canceled:
          next = next.copyWith(status: DownloadStatus.canceled);
        case TaskStatus.waitingToRetry:
          // Keep current status; retry is transient.
          break;
      }
    } else if (u is TaskProgressUpdate) {
      final total = u.expectedFileSize > 0
          ? u.expectedFileSize
          : next.totalBytes;
      final fraction = u.progress;
      final downloaded = total > 0 && fraction >= 0
          ? (total * fraction).toInt()
          : next.downloadedBytes;
      next = next.copyWith(
        totalBytes: total,
        downloadedBytes: downloaded,
      );
    }
    next = next.copyWith(
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000);
    _entries[id] = next;
    // Fire-and-forget persistence — we don't await it on every progress
    // tick to avoid hammering SharedPreferences.
    unawaited(_persist());
    notifyListeners();
  }

  void _loadFromPrefs() {
    final raw = _prefs.getString(_storeKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final j in list) {
        final entry = DownloadEntry.fromJson(j as Map<String, dynamic>);
        _entries[entry.fileId] = entry;
      }
    } catch (_) {
      // Corrupt store — start clean.
    }
  }

  Future<void> _persist() async {
    final list = _entries.values.map((e) => e.toJson()).toList();
    await _prefs.setString(_storeKey, jsonEncode(list));
  }
}
