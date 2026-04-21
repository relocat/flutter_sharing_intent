// SPDX-License-Identifier: Apache-2.0
// ignore_for_file: constant_identifier_names

class SharedFile {
  /// Image or Video path or text
  /// NOTE. for iOS only the file is always copied
  String? value;

  /// Video thumbnail
  String? thumbnail;

  /// Video duration in milliseconds
  int? duration;

  /// Whether its a video or image or file
  SharedMediaType type = SharedMediaType.OTHER;

  /// Mime type of the file.
  /// i.e. image/jpeg, video/mp4, text/plain
  final String? mimeType;

  /// Post message iOS ONLY
  final String? message;

  SharedFile(
      {required this.value,
      this.thumbnail,
      this.duration,
      this.type = SharedMediaType.OTHER,
      this.mimeType,
      this.message});

  SharedFile.fromJson(Map<String, dynamic> json)
      : value = json['value'] ?? json['path'],
        thumbnail = json['thumbnail'],
        duration = json['duration'],
        type = _typeFromJson(json['type']),
        mimeType = json['mimeType'],
        message = json['message'];

  Map<String, dynamic> toMap() {
    return {
      'value': value,
      'thumbnail': thumbnail,
      'duration': duration,
      'type': type.index,
      'mimeType': mimeType,
      'message': message,
    };
  }

  @override
  String toString() {
    return "{ value:$value, thumbnail:$thumbnail, duration:$duration, type:$type, mimeType:$mimeType, message:$message }";
  }
}

/// Safely decode a [SharedMediaType] from a raw JSON integer (FSI-94).
///
/// Direct indexing via `SharedMediaType.values[n]` throws [RangeError] for
/// any value outside the valid range; that crash can be triggered by a
/// malicious share source controlling the EventChannel payload. Returns
/// [SharedMediaType.FILE] as a conservative fallback for unknown indices.
SharedMediaType _typeFromJson(Object? raw) {
  final typeIdx = raw is int ? raw : 0;
  if (typeIdx >= 0 && typeIdx < SharedMediaType.values.length) {
    return SharedMediaType.values[typeIdx];
  }
  return SharedMediaType.FILE; // conservative fallback for unknown indices
}

enum SharedMediaType { TEXT, URL, IMAGE, VIDEO, FILE, WEB_SEARCH, OTHER }
