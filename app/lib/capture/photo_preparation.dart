import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const maxPhotoBytes = 8 * 1024 * 1024;
const maxPhotoPixels = 16000000;

class PhotoPreparationException implements Exception {
  const PhotoPreparationException(this.message);
  final String message;
}

class PreparedPhoto {
  PreparedPhoto(Uint8List bytes, this.mime, this.width, this.height)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final String mime;
  final int width, height;
  String requestFingerprint(String source) {
    // Exact inspected capture-v1 Python JSON array encoding, including spaces.
    final digest = sha256.convert(bytes).toString();
    final input = '["$source", "front", "$mime", "$digest"]';
    return sha256.convert(input.codeUnits).toString();
  }

  String get filename => mime == 'image/png' ? 'capture.png' : 'capture.jpg';
}

Future<PreparedPhoto> preparePhoto(Uint8List bytes) =>
    compute(preparePhotoSync, bytes);

/// Compatibility and metadata preparation only, never an image quality gate.
PreparedPhoto preparePhotoSync(Uint8List bytes) {
  if (bytes.length > maxPhotoBytes) {
    throw const PhotoPreparationException('Choose a JPEG or PNG up to 8 MiB.');
  }
  try {
    final png =
        bytes.length >= 8 &&
        listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!png && !jpeg) {
      throw const PhotoPreparationException(
        'Use a single opaque JPEG or PNG photograph. HEIC, GIF and other formats are not supported.',
      );
    }
    final chunks = png ? _pngChunks(bytes) : _jpegChunks(bytes);
    var orientation = 1;
    var hasExif = false;
    for (final chunk in chunks) {
      if (chunk.exif != null) {
        if (hasExif) {
          throw const PhotoPreparationException(
            'Orientation metadata is ambiguous. Export a new upright photo.',
          );
        }
        hasExif = true;
        orientation = _readOrientation(chunk.exif!);
        if (orientation < 1 || orientation > 8) {
          throw const PhotoPreparationException(
            'Orientation metadata is invalid. Export a new upright photo.',
          );
        }
      }
    }
    final img.Decoder decoder = png ? img.PngDecoder() : img.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null || info.width < 1 || info.height < 1) {
      throw const PhotoPreparationException(
        'This photo is unreadable. Export a new JPEG or PNG.',
      );
    }
    if (info.width * info.height > maxPhotoPixels) {
      throw const PhotoPreparationException(
        'Choose a photo no larger than 16 megapixels.',
      );
    }
    if (info.numFrames != 1) {
      throw const PhotoPreparationException(
        'Use a single photograph, not an animated or multi-frame image.',
      );
    }
    var pixels = decoder.decodeFrame(0);
    if (pixels == null || pixels.hasAlpha || chunks.any((c) => c.transparent)) {
      throw const PhotoPreparationException(
        'Use an opaque JPEG or PNG without transparency.',
      );
    }
    // JPEG's decoder already applies EXIF orientation. PNG's does not.
    if (png && orientation != 1) {
      pixels.exif = img.ExifData()..imageIfd.orientation = orientation;
      pixels = img.bakeOrientation(pixels);
    }
    pixels.exif = img.ExifData();
    pixels.textData = null;
    final Uint8List upload;
    if (orientation == 1) {
      // Drop metadata segments/chunks without changing or recompressing pixels.
      final builder = BytesBuilder(copy: false)
        ..add(bytes.sublist(0, png ? 8 : 2));
      for (final chunk in chunks.where((c) => !c.metadata)) {
        builder.add(chunk.raw);
      }
      upload = builder.takeBytes();
    } else {
      upload = png ? img.encodePng(pixels) : img.encodeJpg(pixels, quality: 95);
    }
    if (upload.length > maxPhotoBytes) {
      throw const PhotoPreparationException(
        'The upright photo exceeds 8 MiB. Export a smaller JPEG or PNG; no photo was uploaded.',
      );
    }
    return PreparedPhoto(
      upload,
      png ? 'image/png' : 'image/jpeg',
      pixels.width,
      pixels.height,
    );
  } on PhotoPreparationException {
    rethrow;
  } catch (_) {
    throw const PhotoPreparationException(
      'This photo could not be read safely. Export a new JPEG or PNG.',
    );
  }
}

class _Chunk {
  _Chunk(
    this.raw, {
    this.exif,
    this.metadata = false,
    this.transparent = false,
  });
  final Uint8List raw;
  final Uint8List? exif;
  final bool metadata, transparent;
}

List<_Chunk> _pngChunks(Uint8List bytes) {
  final chunks = <_Chunk>[];
  var offset = 8;
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) throw const FormatException('PNG chunk');
    final length = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
    final end = offset + 12 + length;
    if (end > bytes.length) throw const FormatException('PNG length');
    final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
    chunks.add(
      _Chunk(
        Uint8List.sublistView(bytes, offset, end),
        exif: type == 'eXif'
            ? Uint8List.sublistView(bytes, offset + 8, end - 4)
            : null,
        metadata: ['eXif', 'tEXt', 'zTXt', 'iTXt', 'tIME'].contains(type),
        transparent: type == 'tRNS',
      ),
    );
    offset = end;
    if (type == 'IEND') {
      if (offset != bytes.length) {
        throw const FormatException('Trailing image data');
      }
      break;
    }
  }
  if (chunks.isEmpty) throw const FormatException('PNG empty');
  return chunks;
}

List<_Chunk> _jpegChunks(Uint8List bytes) {
  final chunks = <_Chunk>[];
  var offset = 2;
  while (offset < bytes.length) {
    final start = offset;
    if (bytes[offset++] != 255) throw const FormatException('JPEG marker');
    while (offset < bytes.length && bytes[offset] == 255) {
      offset++;
    }
    if (offset >= bytes.length) throw const FormatException('JPEG marker');
    final marker = bytes[offset++];
    if (marker == 0xda) {
      chunks.add(_Chunk(Uint8List.sublistView(bytes, start)));
      return chunks;
    }
    if (offset + 2 > bytes.length) throw const FormatException('JPEG segment');
    final length = ByteData.sublistView(bytes, offset, offset + 2).getUint16(0);
    final end = offset + length;
    if (length < 2 || end > bytes.length) {
      throw const FormatException('JPEG length');
    }
    final data = Uint8List.sublistView(bytes, offset + 2, end);
    final isExif =
        marker == 0xe1 &&
        data.length >= 6 &&
        listEquals(data.sublist(0, 6), [69, 120, 105, 102, 0, 0]);
    chunks.add(
      _Chunk(
        Uint8List.sublistView(bytes, start, end),
        exif: isExif ? Uint8List.sublistView(data, 6) : null,
        metadata: [0xe1, 0xed, 0xfe].contains(marker),
      ),
    );
    offset = end;
  }
  throw const FormatException('JPEG scan missing');
}

// Only the TIFF header and orientation tag are needed. No sensitive EXIF
// fields are retained. The pinned library's ExifData.read returns false even
// on success, so validate the orientation directory structurally instead.
int _readOrientation(Uint8List data) {
  if (data.length < 8) throw const FormatException('EXIF header');
  final endian = data[0] == 73 && data[1] == 73
      ? Endian.little
      : data[0] == 77 && data[1] == 77
      ? Endian.big
      : null;
  if (endian == null) throw const FormatException('EXIF byte order');
  final view = ByteData.sublistView(data);
  if (view.getUint16(2, endian) != 42) {
    throw const FormatException('EXIF signature');
  }
  final offset = view.getUint32(4, endian);
  if (offset < 8 || offset + 2 > data.length) {
    throw const FormatException('EXIF directory');
  }
  final count = view.getUint16(offset, endian);
  if (offset + 2 + 12 * count + 4 > data.length) {
    throw const FormatException('EXIF entries');
  }
  int? orientation;
  for (var i = 0; i < count; i++) {
    final p = offset + 2 + 12 * i;
    if (view.getUint16(p, endian) != 0x0112) continue;
    if (orientation != null ||
        view.getUint16(p + 2, endian) != 3 ||
        view.getUint32(p + 4, endian) != 1) {
      throw const FormatException('EXIF orientation');
    }
    orientation = view.getUint16(p + 8, endian);
  }
  return orientation ?? 1;
}
