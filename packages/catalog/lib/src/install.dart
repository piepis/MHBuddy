import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import 'fixture_public_key.dart';

class ContentVault {
  ContentVault({this.quotaBytes = 1 << 30});
  final int quotaBytes;
  int used = 0;
  final Map<String, int> activeNumber = {};
  final Map<String, String> activeRevision = {};
  final Map<String, Map<String, Object?>> staged = {};

  String? revisionFor(String key) => activeRevision[key];
}

class InstallResult {
  InstallResult({required this.ok, this.error, this.activeRevision, this.usedFullPack = false});
  final bool ok;
  final String? error;
  final String? activeRevision;
  final bool usedFullPack;
}

class PackInstaller {
  Future<InstallResult> install({
    required ContentVault vault,
    required Map<String, dynamic> manifest,
    required Uint8List body,
    required String contextKey,
  }) async {
    final previous = vault.revisionFor(contextKey);
    final previousNumber = vault.activeNumber[contextKey] ?? 0;
    final digest = sha256.convert(body).toString();
    if (digest != manifest['sha256']) {
      return InstallResult(ok: false, error: 'HASH_MISMATCH', activeRevision: previous);
    }
    final pub = hexToBytes(fixturePublicKeyHex);
    try {
      final sig = base64Decode(manifest['signature'] as String);
      final ok = await Ed25519().verify(
        utf8.encode(digest),
        signature: Signature(sig, publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
      );
      if (!ok) {
        return InstallResult(ok: false, error: 'BAD_SIGNATURE', activeRevision: previous);
      }
    } catch (_) {
      return InstallResult(ok: false, error: 'BAD_SIGNATURE', activeRevision: previous);
    }
    final diff = manifest['diff'];
    var usedFull = true;
    if (diff is Map && diff['parent'] != null) {
      if (diff['parent'] != previous) {
        usedFull = true;
      }
    }
    if (body.length > vault.quotaBytes - 0 && vault.used + body.length > vault.quotaBytes && previous != null) {
      return InstallResult(ok: false, error: 'QUOTA', activeRevision: previous);
    }
    if (vault.used + body.length > vault.quotaBytes && previous == null && body.length > vault.quotaBytes) {
      return InstallResult(ok: false, error: 'QUOTA', activeRevision: previous);
    }
    final number = (manifest['revisionNumber'] as num?)?.toInt() ?? 0;
    vault.staged['$contextKey@$number'] = {'bytes': body.length, 'sha256': digest};
    if (number < previousNumber) {
      return InstallResult(ok: true, error: 'KEPT_NEWER', activeRevision: previous, usedFullPack: usedFull);
    }
    vault.activeNumber[contextKey] = number;
    vault.activeRevision[contextKey] = manifest['dataRevision'] as String? ?? '$number';
    vault.used += body.length;
    return InstallResult(ok: true, activeRevision: vault.activeRevision[contextKey], usedFullPack: usedFull);
  }
}

Uint8List hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
