import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/src/models/chapter_marker.dart';

class ChewieProgressColors {
  ChewieProgressColors({
    Color playedColor = const Color.fromRGBO(255, 0, 0, 0.7),
    Color bufferedColor = const Color.fromRGBO(30, 30, 200, 0.2),
    Color downloadedColor = const Color.fromRGBO(0, 255, 0, 0.4),
    Color handleColor = const Color.fromRGBO(200, 200, 200, 1.0),
    Color backgroundColor = const Color.fromRGBO(200, 200, 200, 0.5),
    this.chapterMarkers = const [],
    this.downloadedRanges = const [],
  }) : playedPaint = Paint()..color = playedColor,
       bufferedPaint = Paint()..color = bufferedColor,
       downloadedPaint = Paint()..color = downloadedColor,
       handlePaint = Paint()..color = handleColor,
       backgroundPaint = Paint()..color = backgroundColor;

  final Paint playedPaint;
  final Paint bufferedPaint;
  final Paint downloadedPaint;
  final Paint handlePaint;
  final Paint backgroundPaint;

  /// List of chapter markers to display on the progress bar
  final List<ChapterMarker> chapterMarkers;

  /// List of downloaded/cached video ranges (start and end duration)
  /// Each range represents a portion of the video that has been downloaded
  final List<DurationRange> downloadedRanges;
}
