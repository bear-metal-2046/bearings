import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const maxFlashCardDeckPayloadBytes = 2048;
const maxFlashCardDeckOverrides = 65536;
const maxFlashCardDeckQrCodeLength = 3000;
const _base41 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\$*+-.';

// Wire IDs are permanent: never reorder or remove entries. New emoji can use
// the UTF-8 escape (ID 0), so extending this table needs a new format version.
const _emojiTable = [
  '🐻',
  '🤖',
  '🚀',
  '⚡',
  '🔥',
  '⭐',
  '🏆',
  '🎯',
  '🦊',
  '🐼',
  '🐸',
  '🐯',
  '🦁',
  '🐙',
  '🦄',
  '🐲',
  '🍀',
  '🌻',
  '🌵',
  '🌈',
  '🌙',
  '🪐',
  '☄️',
  '🌊',
  '🍕',
  '🍩',
  '🍉',
  '🍋',
  '🍒',
  '🥑',
  '🍿',
  '🧋',
  '🎸',
  '🎮',
  '🎲',
  '🧩',
  '💎',
  '🧲',
  '🛠️',
  '🧠',
  '🏎️',
  '🚁',
  '🛸',
  '⛵',
  '🎈',
  '🎉',
  '👑',
  '🦋',
];

typedef FlashCardDeckFields = ({
  String name,
  String emoji,
  List<String> events,
  Map<String, List<int>> exclusions,
});

/// BFC3 binary fields, in order:
/// - UTF-8 name, emoji ID (0 escapes to a UTF-8 string)
/// - year count; each year: offset from 1992, suffix count, UTF-8 suffixes
/// - override count; each group: sorted event ordinal, mode, mode-specific data
/// All integers/lengths are unsigned LEB128. Strings have byte-length prefixes.
Uint8List encodeFlashCardDeckFields(FlashCardDeckFields fields) {
  final out = _Writer()..string(fields.name);
  final emoji = _emojiTable.indexOf(fields.emoji) + 1;
  out.uint(emoji);
  if (emoji == 0) out.string(fields.emoji);
  final years = <String, List<String>>{};
  for (final event in fields.events) {
    years.putIfAbsent(event.substring(0, 4), () => []).add(event.substring(4));
  }
  out.uint(years.length);
  for (final entry in years.entries) {
    out.uint(int.parse(entry.key) - 1992);
    out.uint(entry.value.length);
    for (final suffix in entry.value) {
      out.string(suffix);
    }
  }
  out.uint(fields.exclusions.length);
  for (var event = 0; event < fields.events.length; event++) {
    final indexes = fields.exclusions[fields.events[event]];
    if (indexes == null) continue;
    out.uint(event);
    out.bytes.addAll(_encodeIndexes(indexes));
  }
  if (out.bytes.length > maxFlashCardDeckPayloadBytes) {
    throw const FormatException(
      'Use fewer team overrides or events to fit the deck code.',
    );
  }
  return Uint8List.fromList(out.bytes);
}

// Mode 0: count, then gaps (first = index; later = index - previous - 1).
// Mode 1: range count, then gap from previous range's end and length minus one.
// Mode 2: bit count, then bytes with the lowest index in the least-significant
// bit. The final bit is set; unused bits in the last byte are zero.
List<int> _encodeIndexes(List<int> indexes) {
  final sparse = _Writer()
    ..uint(0)
    ..uint(indexes.length);
  var previous = -1;
  final ranges = <(int, int)>[];
  for (final index in indexes) {
    sparse.uint(index - previous - 1);
    if (ranges.isNotEmpty && index == ranges.last.$2 + 1) {
      ranges[ranges.length - 1] = (ranges.last.$1, index);
    } else {
      ranges.add((index, index));
    }
    previous = index;
  }
  final runs = _Writer()
    ..uint(1)
    ..uint(ranges.length);
  previous = -1;
  for (final (start, end) in ranges) {
    runs.uint(start - previous - 1);
    runs.uint(end - start);
    previous = end;
  }
  final bitmap = _Writer()
    ..uint(2)
    ..uint(indexes.last + 1);
  final bits = Uint8List((indexes.last + 8) ~/ 8);
  for (final index in indexes) {
    bits[index ~/ 8] |= 1 << (index % 8);
  }
  bitmap.bytes.addAll(bits);
  var best = sparse.bytes;
  for (final candidate in [runs.bytes, bitmap.bytes]) {
    if (candidate.length < best.length) best = candidate;
  }
  return best;
}

FlashCardDeckFields decodeFlashCardDeckFields(List<int> payload) {
  final input = _Reader(payload);
  final name = input.string(240);
  final emojiId = input.uint(_emojiTable.length);
  final emoji = emojiId == 0 ? input.string(64) : _emojiTable[emojiId - 1];
  final yearCount = input.uint(32);
  final events = <String>[];
  var previousYear = -1;
  for (var i = 0; i < yearCount; i++) {
    final year = input.uint(108);
    if (year <= previousYear) {
      throw const FormatException('Invalid event years.');
    }
    previousYear = year;
    final count = input.uint(32 - events.length);
    if (count == 0) throw const FormatException('Missing events.');
    var previousSuffix = '';
    for (var j = 0; j < count; j++) {
      final suffix = input.string(32);
      if (!RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(suffix) ||
          suffix.compareTo(previousSuffix) <= 0) {
        throw const FormatException('Invalid event suffix.');
      }
      previousSuffix = suffix;
      events.add('${year + 1992}$suffix');
    }
  }
  if (events.isEmpty) throw const FormatException('Missing events.');
  final groupCount = input.uint(events.length);
  final exclusions = <String, List<int>>{};
  var previousEvent = -1;
  var remaining = maxFlashCardDeckOverrides;
  for (var i = 0; i < groupCount; i++) {
    final event = input.uint(events.length - 1);
    if (event <= previousEvent) {
      throw const FormatException('Invalid event reference.');
    }
    previousEvent = event;
    final indexes = _decodeIndexes(input, remaining);
    if (indexes.isEmpty) throw const FormatException('Empty team overrides.');
    remaining -= indexes.length;
    exclusions[events[event]] = indexes;
  }
  if (!input.done) throw const FormatException('Unexpected deck data.');
  return (name: name, emoji: emoji, events: events, exclusions: exclusions);
}

List<int> _decodeIndexes(_Reader input, int remaining) {
  final mode = input.uint(2);
  final result = <int>[];
  switch (mode) {
    case 0:
      final count = input.uint(remaining);
      var previous = -1;
      for (var i = 0; i < count; i++) {
        previous += input.uint(65535) + 1;
        if (previous > 65535) {
          throw const FormatException('Invalid team index.');
        }
        result.add(previous);
      }
    case 1:
      final count = input.uint(remaining);
      var previous = -1;
      for (var i = 0; i < count; i++) {
        final start = previous + input.uint(65535) + 1;
        final length = input.uint(65535) + 1;
        final end = start + length - 1;
        if (end > 65535 || result.length + length > remaining) {
          throw const FormatException('Invalid team range.');
        }
        for (var index = start; index <= end; index++) {
          result.add(index);
        }
        previous = end;
      }
    case 2:
      final count = input.uint(65536);
      if (count == 0) throw const FormatException('Empty team bitmap.');
      final bytes = input.take((count + 7) ~/ 8);
      final lastBit = 1 << ((count - 1) % 8);
      if (bytes.last & lastBit == 0 || bytes.last >= lastBit * 2) {
        throw const FormatException('Invalid team bitmap.');
      }
      for (var index = 0; index < count; index++) {
        if (bytes[index ~/ 8] & (1 << (index % 8)) != 0) {
          if (result.length >= remaining) {
            throw const FormatException('Too many overrides.');
          }
          result.add(index);
        }
      }
  }
  return result;
}

/// Each destination chooses raw/compressed independently after text encoding.
/// U = unpadded Base64URL; Q = Base41. N = raw; Z = zlib.
({String text, String qr}) encodeFlashCardDeckEnvelopes(List<int> payload) {
  final compressed = const ZLibEncoder().encode(payload, level: 9);
  String envelope({required bool qr}) {
    String encode(List<int> bytes) => qr
        ? encodeFlashCardBase41(bytes)
        : base64UrlEncode(bytes).replaceAll('=', '');
    final raw = encode(payload);
    final zipped = encode(compressed);
    final useCompression = zipped.length < raw.length;
    return 'BFC3:${qr ? 'Q' : 'U'}${useCompression ? 'Z' : 'N'}:${useCompression ? zipped : raw}';
  }

  return (text: envelope(qr: false), qr: envelope(qr: true));
}

FlashCardDeckFields decodeFlashCardDeckEnvelope(String code) {
  if (code.length < 9 || code[7] != ':' || (code[5] != 'U' && code[5] != 'Q')) {
    throw const FormatException('Invalid deck encoding.');
  }
  final encoded = code.substring(8);
  final List<int> bytes;
  if (code[5] == 'Q') {
    bytes = decodeFlashCardBase41(encoded);
  } else {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
      throw const FormatException('Invalid deck encoding.');
    }
    bytes = base64Url.decode(base64Url.normalize(encoded));
  }
  final payload = switch (code[6]) {
    'N' => bytes,
    'Z' => decodeFlashCardDeckZlib(bytes),
    _ => throw const FormatException('Invalid deck compression.'),
  };
  if (payload.length > maxFlashCardDeckPayloadBytes) {
    throw const FormatException('The deck payload is too large.');
  }
  return decodeFlashCardDeckFields(payload);
}

String encodeFlashCardBase41(List<int> bytes) {
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i += 2) {
    final pair = i + 1 < bytes.length;
    var value = pair ? bytes[i] * 256 + bytes[i + 1] : bytes[i];
    for (var digit = 0; digit < (pair ? 3 : 2); digit++) {
      out.write(_base41[value % 41]);
      value ~/= 41;
    }
  }
  return out.toString();
}

Uint8List decodeFlashCardBase41(String encoded) {
  if (encoded.isEmpty || encoded.length % 3 == 1) {
    throw const FormatException('Invalid Base41 length.');
  }
  final out = <int>[];
  for (var i = 0; i < encoded.length; i += 3) {
    final count = encoded.length - i >= 3 ? 3 : 2;
    var value = 0;
    var multiplier = 1;
    for (var digit = 0; digit < count; digit++) {
      final decoded = _base41.indexOf(encoded[i + digit]);
      if (decoded < 0) throw const FormatException('Invalid Base41 character.');
      value += decoded * multiplier;
      multiplier *= 41;
    }
    if (value > (count == 3 ? 65535 : 255)) {
      throw const FormatException('Invalid Base41 value.');
    }
    if (count == 3) out.add(value ~/ 256);
    out.add(value % 256);
  }
  return Uint8List.fromList(out);
}

/// Use the same bounded inflater on native and web. Checking only after the
/// platform decoder returns would allow a tiny input to allocate a huge output.
List<int> decodeFlashCardDeckZlib(List<int> bytes) {
  if (bytes.length < 6 ||
      bytes[0] & 15 != 8 ||
      bytes[0] >> 4 > 7 ||
      (bytes[0] * 256 + bytes[1]) % 31 != 0 ||
      bytes[1] & 32 != 0) {
    throw const FormatException('Invalid compressed deck.');
  }
  final input = InputStream(bytes.sublist(2, bytes.length - 4));
  final out = _BoundedOutput();
  Inflate.stream(input, out);
  final payload = out.getBytes();
  var checksum = 0;
  for (final byte in bytes.skip(bytes.length - 4)) {
    checksum = checksum * 256 + byte;
  }
  if (!input.isEOS || getAdler32(payload) != checksum) {
    throw const FormatException('Invalid compressed deck checksum.');
  }
  return payload;
}

class _BoundedOutput extends OutputStream {
  _BoundedOutput() : super(size: maxFlashCardDeckPayloadBytes);

  void _check(int count) {
    if (length + count > maxFlashCardDeckPayloadBytes) {
      throw const FormatException('The deck payload is too large.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    _check(len ?? bytes.length);
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    _check(stream.length);
    super.writeInputStream(stream);
  }
}

class _Writer {
  final bytes = <int>[];

  void uint(int value) {
    if (value < 0 || value > 65536) {
      throw const FormatException('Invalid deck integer.');
    }
    do {
      final next = value & 127;
      value >>= 7;
      bytes.add(next | (value == 0 ? 0 : 128));
    } while (value != 0);
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    uint(encoded.length);
    bytes.addAll(encoded);
  }
}

class _Reader {
  _Reader(this.bytes);
  final List<int> bytes;
  int offset = 0;
  bool get done => offset == bytes.length;

  int uint(int max) {
    var value = 0;
    for (var shift = 0; shift <= 14; shift += 7) {
      if (done) throw const FormatException('Truncated deck.');
      final byte = bytes[offset++];
      value |= (byte & 127) << shift;
      if (byte & 128 == 0) {
        if (value > max || (shift > 0 && byte == 0)) {
          throw const FormatException('Invalid deck integer.');
        }
        return value;
      }
    }
    throw const FormatException('Invalid deck integer.');
  }

  List<int> take(int length) {
    if (offset + length > bytes.length) {
      throw const FormatException('Truncated deck.');
    }
    final result = bytes.sublist(offset, offset + length);
    offset += length;
    return result;
  }

  String string(int maxBytes) => utf8.decode(take(uint(maxBytes)));
}
