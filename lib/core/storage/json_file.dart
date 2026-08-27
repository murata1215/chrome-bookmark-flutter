import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 単純な非同期 mutex。同一 [JsonFile] インスタンスに対する read-modify-write を
/// 直列化する（★・open・pull の3つの flush トリガーが交錯しないように）。
class AsyncMutex {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        completer.complete();
      }
    });
  }
}

/// JSON ファイルの原子的な読み書き。
///
/// 書き込みは `<path>.tmp` に書いて `flush()` してから `rename()` する
/// （POSIX / NTFS いずれでも rename は原子的）。このアプリはタップの度に
/// 必ずバックグラウンドへ行く（Chrome を起動するので）ため、書き込み中の
/// kill は必ず起きる前提で作る（truncate 書き＋`catch(_) => []` は真似しない）。
///
/// [keepBackup] が true の場合（snapshot.json 用）、書き込み前に現行ファイルを
/// `<path>.bak` へコピーし、本体の読み込み・パースに失敗したら `.bak` を試す。
class JsonFile {
  JsonFile(this.file, {this.keepBackup = false});

  final File file;
  final bool keepBackup;
  final AsyncMutex _mutex = AsyncMutex();

  File get _tmpFile => File('${file.path}.tmp');
  File get _bakFile => File('${file.path}.bak');

  /// 読み込み。存在しない・空・パース不能なら null
  /// （[keepBackup] のときは `.bak` へフォールバックしてから null）。
  Future<Map<String, dynamic>?> readMap() {
    return _mutex.run(() async {
      final primary = await _tryRead(file);
      if (primary != null) return primary;
      if (keepBackup) {
        final backup = await _tryRead(_bakFile);
        if (backup != null) return backup;
      }
      return null;
    });
  }

  Future<Map<String, dynamic>?> _tryRead(File f) async {
    try {
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      if (text.isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 原子的書き込み。
  Future<void> writeMap(Map<String, dynamic> data) {
    return _mutex.run(() async {
      await file.parent.create(recursive: true);
      if (keepBackup && await file.exists()) {
        try {
          await file.copy(_bakFile.path);
        } catch (_) {
          // バックアップ失敗は致命的ではない（次回の成功時に更新される）。
        }
      }
      final raf = await _tmpFile.open(mode: FileMode.write);
      try {
        await raf.writeString(jsonEncode(data));
        await raf.flush();
      } finally {
        await raf.close();
      }
      await _tmpFile.rename(file.path);
    });
  }

  /// 本体・.bak・.tmp を全て削除（unpair 時の全消去用）。
  Future<void> delete() {
    return _mutex.run(() async {
      for (final f in [file, _bakFile, _tmpFile]) {
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {
            // 消去自体の失敗は無視（次回起動時に上書きされる）。
          }
        }
      }
    });
  }
}
