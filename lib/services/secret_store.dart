import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../db/repository.dart';

/// API kalitni saqlash. Windows'da DPAPI (CryptProtectData) bilan joriy foydalanuvchi
/// hisobiga bog'lab shifrlanadi — boshqa foydalanuvchi yoki kompyuter uni ocha olmaydi.
/// Boshqa tizimlarda kalit bazada base64 ko'rinishida saqlanadi.
class SecretStore {
  SecretStore(this.repo);
  final Repository repo;

  static const _keyWin = 'api_key_dpapi';
  static const _keyOther = 'api_key_b64';

  Future<String> read() async {
    try {
      if (Platform.isWindows) {
        final v = await repo.getSetting(_keyWin);
        if (v == null || v.isEmpty) return '';
        return utf8.decode(_Dpapi.unprotect(base64Decode(v)));
      }
      final v = await repo.getSetting(_keyOther);
      return v == null || v.isEmpty ? '' : utf8.decode(base64Decode(v));
    } catch (_) {
      return '';
    }
  }

  Future<void> write(String secret) async {
    if (Platform.isWindows) {
      final enc = secret.isEmpty ? '' : base64Encode(_Dpapi.protect(utf8.encode(secret)));
      await repo.setSetting(_keyWin, enc);
    } else {
      await repo.setSetting(_keyOther, secret.isEmpty ? '' : base64Encode(utf8.encode(secret)));
    }
  }
}

final class _Blob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

typedef _CryptNative = Int32 Function(Pointer<_Blob>, Pointer<Utf16>, Pointer<_Blob>, Pointer<Void>,
    Pointer<Void>, Uint32, Pointer<_Blob>);
typedef _CryptDart = int Function(Pointer<_Blob>, Pointer<Utf16>, Pointer<_Blob>, Pointer<Void>,
    Pointer<Void>, int, Pointer<_Blob>);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

class _Dpapi {
  static const _uiForbidden = 0x1; // CRYPTPROTECT_UI_FORBIDDEN

  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _protect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptProtectData');
  static final _unprotect = _crypt32.lookupFunction<_CryptNative, _CryptDart>('CryptUnprotectData');
  static final _localFree = _kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');

  static Uint8List protect(List<int> data) => _run(data, _protect);
  static Uint8List unprotect(List<int> data) => _run(data, _unprotect);

  static Uint8List _run(List<int> data, _CryptDart fn) {
    final input = calloc<_Blob>();
    final output = calloc<_Blob>();
    final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buf.asTypedList(data.length).setAll(0, data);
      input.ref
        ..cbData = data.length
        ..pbData = buf;
      final ok = fn(input, nullptr, nullptr, nullptr, nullptr, _uiForbidden, output);
      if (ok == 0) throw StateError('DPAPI error');
      final result = Uint8List.fromList(output.ref.pbData.asTypedList(output.ref.cbData));
      _localFree(output.ref.pbData.cast());
      return result;
    } finally {
      calloc.free(buf);
      calloc.free(input);
      calloc.free(output);
    }
  }
}
