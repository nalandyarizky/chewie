import 'package:flutter/material.dart';

/// Represents a chapter marker on the video progress bar.
/// 
/// A chapter marker is displayed as a colored circle at a specific duration
/// in the video timeline.
class ChapterMarker {
  const ChapterMarker({
    required this.duration,
    required this.color,
    this.radius = 4.0,
    this.title,
  });

  /// The duration at which this chapter marker should appear
  final Duration duration;

  /// The color of the chapter marker circle
  final Color color;

  /// The radius of the chapter marker circle (default: 4.0)
  final double radius;

  /// Optional title for the chapter marker
  final String? title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChapterMarker &&
          runtimeType == other.runtimeType &&
          duration == other.duration &&
          color == other.color &&
          radius == other.radius &&
          title == other.title;

  @override
  int get hashCode =>
      duration.hashCode ^ color.hashCode ^ radius.hashCode ^ title.hashCode;

  @override
  String toString() {
    return 'ChapterMarker{duration: $duration, color: $color, radius: $radius, title: $title}';
  }

  ChapterMarker copyWith({
    Duration? duration,
    Color? color,
    double? radius,
    String? title,
  }) {
    return ChapterMarker(
      duration: duration ?? this.duration,
      color: color ?? this.color,
      radius: radius ?? this.radius,
      title: title ?? this.title,
    );
  }
}
