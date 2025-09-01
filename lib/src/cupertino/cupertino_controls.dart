import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chewie/src/animated_play_pause.dart';
import 'package:chewie/src/center_play_button.dart';
import 'package:chewie/src/center_seek_button.dart';
import 'package:chewie/src/chewie_player.dart';
import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/cupertino/cupertino_progress_bar.dart';
import 'package:chewie/src/cupertino/widgets/cupertino_options_dialog.dart';
import 'package:chewie/src/helpers/utils.dart';
import 'package:chewie/src/models/option_item.dart';
import 'package:chewie/src/models/subtitle_model.dart';
import 'package:chewie/src/notifiers/index.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class CupertinoControls extends StatefulWidget {
  const CupertinoControls({required this.backgroundColor, required this.iconColor, this.showPlayButton = true, super.key});

  final Color backgroundColor;
  final Color iconColor;
  final bool showPlayButton;

  @override
  State<StatefulWidget> createState() {
    return _CupertinoControlsState();
  }
}

class _CupertinoControlsState extends State<CupertinoControls> with SingleTickerProviderStateMixin {
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  final marginSize = 5.0;
  Timer? _expandCollapseTimer;
  Timer? _initTimer;
  bool _dragging = false;
  Duration? _subtitlesPosition;
  bool _subtitleOn = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;
  bool _displayTapped = false;
  double selectedSpeed = 1.0;
  late VideoPlayerController controller;

  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;
  ChewieController? _chewieController;
  bool _chewieControllerListenerAttached = false;

  @override
  void initState() {
    super.initState();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder != null
          ? chewieController.errorBuilder!(context, chewieController.videoPlayerController.value.errorDescription!)
          : const Center(child: Icon(CupertinoIcons.exclamationmark_circle, color: Colors.white, size: 42));
    }

    final backgroundColor = widget.backgroundColor;
    final iconColor = widget.iconColor;
    final orientation = MediaQuery.of(context).orientation;
    final barHeight = orientation == Orientation.portrait ? 30.0 : 47.0;

    return MouseRegion(
      onHover: (_) => _cancelAndRestartTimer(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => _playPause(),
            child: AbsorbPointer(
              absorbing: controller.value.isPlaying,
              child: Stack(
                children: [
                  if (_displayBufferingIndicator)
                    _chewieController?.bufferingBuilder?.call(context) ?? const Center(child: CircularProgressIndicator())
                  else
                    _buildHitArea(),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[Spacer(), _buildBottomBar(backgroundColor, iconColor, barHeight)],
                  ),
                ],
              ),
            ),
          ),
          // Place action bar outside the GestureDetector to avoid conflicts
          _buildActionBar(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _expandCollapseTimer?.cancel();
    _initTimer?.cancel();
    if (_chewieControllerListenerAttached) {
      try {
        chewieController.removeListener(_onChewieControllerChanged);
      } catch (_) {}
      _chewieControllerListenerAttached = false;
    }
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  GestureDetector _buildOptionsButton(Color iconColor, double barHeight) {
    final options = <OptionItem>[];

    if (chewieController.additionalOptions != null && chewieController.additionalOptions!(context).isNotEmpty) {
      options.addAll(chewieController.additionalOptions!(context));
    }

    return GestureDetector(
      onTap: () async {
        _hideTimer?.cancel();

        if (chewieController.optionsBuilder != null) {
          await chewieController.optionsBuilder!(context, options);
        } else {
          await showCupertinoModalPopup<OptionItem>(
            context: context,
            semanticsDismissible: true,
            useRootNavigator: chewieController.useRootNavigator,
            builder:
                (context) =>
                    CupertinoOptionsDialog(options: options, cancelButtonText: chewieController.optionsTranslation?.cancelButtonText),
          );
          if (_latestValue.isPlaying) {
            _startHideTimer();
          }
        }
      },
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 4.0, right: 8.0),
        margin: const EdgeInsets.only(right: 6.0),
        child: Icon(Icons.more_vert, color: iconColor, size: 18),
      ),
    );
  }

  Widget _buildBottomBar(Color backgroundColor, Color iconColor, double barHeight) {
    return SafeArea(
      bottom: chewieController.isFullScreen,
      minimum: chewieController.controlsSafeAreaMinimum,
      child: AnimatedOpacity(
        opacity: 1,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: double.infinity,
          color: Colors.transparent,
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.symmetric(horizontal: marginSize, vertical: marginSize),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10.0),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Container(
                width: double.infinity,
                height: barHeight,
                color: backgroundColor,
                child:
                    chewieController.isLive
                        ? Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[_buildPlayPause(controller, iconColor, barHeight), _buildLive(iconColor)],
                        )
                        : Row(
                          children: <Widget>[
                            // Only show skip buttons if not in fullscreen OR if showSkipButtonsInFullScreen is true
                            if (!chewieController.isFullScreen || chewieController.showSkipButtonsInFullScreen)
                              _buildSkipBack(iconColor, barHeight),
                            _buildPlayPause(controller, iconColor, barHeight),
                            if (!chewieController.isFullScreen || chewieController.showSkipButtonsInFullScreen)
                              _buildSkipForward(iconColor, barHeight),
                            _buildPosition(iconColor),
                            _buildProgressBar(),
                            _buildRemaining(iconColor),
                            _buildSubtitleToggle(iconColor, barHeight),
                            if (chewieController.allowPlaybackSpeedChanging) _buildSpeedButton(controller, iconColor, barHeight),
                            if (chewieController.additionalOptions != null && chewieController.additionalOptions!(context).isNotEmpty)
                              _buildOptionsButton(iconColor, barHeight),
                          ],
                        ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLive(Color iconColor) {
    return Padding(padding: const EdgeInsets.only(right: 12.0), child: Text('LIVE', style: TextStyle(color: iconColor, fontSize: 12.0)));
  }

  Widget _buildHitArea() {
    final bool isFinished = (_latestValue.position >= _latestValue.duration) && _latestValue.duration.inSeconds > 0;
    final bool showPlayButton = widget.showPlayButton && !_dragging && !notifier.hideStuff;

    // Check if skip buttons should be shown in fullscreen
    final bool showSkipButtons =
        !isFinished && !chewieController.isLive && (!chewieController.isFullScreen || chewieController.showSkipButtonsInFullScreen);

    return GestureDetector(
      onTap: () {
        if (_latestValue.isPlaying) {
          if (_chewieController?.pauseOnBackgroundTap ?? false) {
            _playPause();
            _cancelAndRestartTimer();
          } else {
            if (_displayTapped) {
              setState(() {
                notifier.hideStuff = true;
              });
            } else {
              _cancelAndRestartTimer();
            }
          }
        } else {
          _playPause();

          setState(() {
            notifier.hideStuff = true;
          });
        }
      },
      child: Visibility(
        visible: !controller.value.isPlaying,
        child: Container(
          alignment: Alignment.center,
          color: Colors.transparent,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showSkipButtons)
                CenterSeekButton(
                  iconData: CupertinoIcons.gobackward_15,
                  backgroundColor: widget.backgroundColor,
                  iconColor: widget.iconColor,
                  show: showPlayButton,
                  onPressed: _seekBackward, // Use seekBackward for 10 sec
                ),
              CenterPlayButton(
                backgroundColor: widget.backgroundColor,
                iconColor: widget.iconColor,
                isFinished: isFinished,
                isPlaying: controller.value.isPlaying,
                show: showPlayButton,
                onPressed: _playPause,
              ),
              if (showSkipButtons)
                CenterSeekButton(
                  iconData: CupertinoIcons.goforward_15,
                  backgroundColor: widget.backgroundColor,
                  iconColor: widget.iconColor,
                  show: showPlayButton,
                  onPressed: _seekForward, // Use seekForward for 10 sec
                ),
            ],
          ),
        ),
      ),
    );
  }

  GestureDetector _buildPlayPause(VideoPlayerController controller, Color iconColor, double barHeight) {
    return GestureDetector(
      onTap: _playPause,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
        child: AnimatedPlayPause(color: widget.iconColor, playing: controller.value.isPlaying),
      ),
    );
  }

  Widget _buildPosition(Color iconColor) {
    final position = _latestValue.position;

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Text(formatDuration(position), style: TextStyle(color: iconColor, fontSize: 12.0)),
    );
  }

  Widget _buildRemaining(Color iconColor) {
    final position = _latestValue.duration - _latestValue.position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Text('-${formatDuration(position)}', style: TextStyle(color: iconColor, fontSize: 12.0)),
    );
  }

  Widget _buildSubtitleToggle(Color iconColor, double barHeight) {
    //if don't have subtitle hiden button
    if (chewieController.subtitle?.isEmpty ?? true) {
      return const SizedBox();
    }
    return GestureDetector(
      onTap: _subtitleToggle,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        margin: const EdgeInsets.only(right: 10.0),
        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
        child: Icon(Icons.subtitles, color: _subtitleOn ? iconColor : Colors.grey[700], size: 16.0),
      ),
    );
  }

  void _subtitleToggle() {
    setState(() {
      _subtitleOn = !_subtitleOn;
    });
  }

  GestureDetector _buildSkipBack(Color iconColor, double barHeight) {
    return GestureDetector(
      onTap: _skipBack,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        margin: const EdgeInsets.only(left: 10.0),
        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
        child: Icon(CupertinoIcons.gobackward_15, color: iconColor, size: 18.0),
      ),
    );
  }

  GestureDetector _buildSkipForward(Color iconColor, double barHeight) {
    return GestureDetector(
      onTap: _skipForward,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 8.0),
        margin: const EdgeInsets.only(right: 8.0),
        child: Icon(CupertinoIcons.goforward_15, color: iconColor, size: 18.0),
      ),
    );
  }

  GestureDetector _buildSpeedButton(VideoPlayerController controller, Color iconColor, double barHeight) {
    return GestureDetector(
      onTap: () async {
        _hideTimer?.cancel();

        final chosenSpeed = await showCupertinoModalPopup<double>(
          context: context,
          semanticsDismissible: true,
          useRootNavigator: chewieController.useRootNavigator,
          builder: (context) => _PlaybackSpeedDialog(speeds: chewieController.playbackSpeeds, selected: _latestValue.playbackSpeed),
        );

        if (chosenSpeed != null) {
          controller.setPlaybackSpeed(chosenSpeed);

          selectedSpeed = chosenSpeed;
        }

        if (_latestValue.isPlaying) {
          _startHideTimer();
        }
      },
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 8.0),
        margin: const EdgeInsets.only(right: 8.0),
        child: Transform(
          alignment: Alignment.center,
          transform:
              Matrix4.skewY(0.0)
                ..rotateX(math.pi)
                ..rotateZ(math.pi * 0.8),
          child: Icon(Icons.speed, color: iconColor, size: 18.0),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (notifier.hideStuff || controller.value.isPlaying) ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.7), Colors.black.withValues(alpha: 0.3), Colors.transparent],
              stops: const [0.0, 0.7, 1.0],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Use MediaQuery to detect if we're in landscape mode (likely fullscreen)
              final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
              final shouldUseFullscreenLayout = chewieController.isFullScreen || chewieController.fullScreenByDefault || isLandscape;
              final mq = MediaQuery.of(context);
              final screenWidth = mq.size.width;

              if (shouldUseFullscreenLayout && constraints.maxWidth < screenWidth * 0.9) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted)
                    Future.delayed(const Duration(milliseconds: 120), () {
                      if (mounted) setState(() {});
                    });
                });
              }

              return shouldUseFullscreenLayout
                  ? Padding(
                    padding: EdgeInsets.only(top: mq.padding.top + 16, left: 16, right: 16, bottom: 16),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            if (chewieController.onBack != null) {
                              chewieController.onBack!();
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                        ),
                        Expanded(
                          child: Text(
                            chewieController.videoTitle ?? '',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w400),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                  : SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              if (chewieController.onBack != null) {
                                chewieController.onBack!();
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
                          ),
                          Expanded(
                            child: Text(
                              chewieController.videoTitle ?? '',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w400),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
            },
          ),
        ),
      ),
    );
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    _subtitleOn = chewieController.showSubtitles && (chewieController.subtitle?.isNotEmpty ?? false);
    controller.addListener(_updateState);

    _updateState();

    // Attach a listener (only once) so layout updates when fullscreen state changes early
    if (!_chewieControllerListenerAttached) {
      chewieController.addListener(_onChewieControllerChanged);
      _chewieControllerListenerAttached = true;
    }

    // Post-frame rebuild to capture fullscreen constraints on very first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (chewieController.fullScreenByDefault || chewieController.isFullScreen) {
        setState(() {});
      }
    });

    // Second delayed rebuild (after potential orientation/layout settle)
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted) return;
      if (chewieController.fullScreenByDefault || chewieController.isFullScreen) {
        setState(() {});
      }
    });

    if (controller.value.isPlaying || chewieController.autoPlay) {
      _startHideTimer();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        setState(() {
          notifier.hideStuff = false;
        });
      });
    }
  }

  void _onChewieControllerChanged() {
    if (!mounted) return;
    setState(() {}); // Rebuild to ensure action bar uses correct width right away
  }

  void _onExpandCollapse() {
    setState(() {
      notifier.hideStuff = true;

      chewieController.toggleFullScreen();
      _expandCollapseTimer = Timer(const Duration(milliseconds: 300), () {
        setState(() {
          _cancelAndRestartTimer();
        });
      });
    });
  }

  Widget _buildProgressBar() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: CupertinoVideoProgressBar(
          controller,
          onDragStart: () {
            setState(() {
              _dragging = true;
            });

            _hideTimer?.cancel();
          },
          onDragUpdate: () {
            _hideTimer?.cancel();
          },
          onDragEnd: () {
            setState(() {
              _dragging = false;
            });

            _startHideTimer();
          },
          colors: _getProgressColorsWithChapterMarkers(),
          draggableProgressBar: chewieController.draggableProgressBar,
          showProgressHandle: chewieController.showProgressHandle,
        ),
      ),
    );
  }

  ChewieProgressColors _getProgressColorsWithChapterMarkers() {
    if (chewieController.cupertinoProgressColors != null) {
      // If user provided custom colors, create a new instance with chapter markers and downloaded ranges
      return ChewieProgressColors(
        playedColor: chewieController.cupertinoProgressColors!.playedPaint.color,
        handleColor: chewieController.cupertinoProgressColors!.handlePaint.color,
        bufferedColor: chewieController.cupertinoProgressColors!.bufferedPaint.color,
        backgroundColor: chewieController.cupertinoProgressColors!.backgroundPaint.color,
        downloadedColor: chewieController.cupertinoProgressColors!.downloadedPaint.color,
        chapterMarkers: chewieController.chapterMarkers,
        downloadedRanges: chewieController.cupertinoProgressColors!.downloadedRanges,
      );
    } else {
      // Use default cupertino colors with chapter markers
      return ChewieProgressColors(
        playedColor: const Color.fromARGB(120, 255, 255, 255),
        handleColor: const Color.fromARGB(255, 255, 255, 255),
        bufferedColor: const Color.fromARGB(60, 255, 255, 255),
        backgroundColor: const Color.fromARGB(20, 255, 255, 255),
        downloadedColor: const Color.fromARGB(80, 0, 255, 0),
        chapterMarkers: chewieController.chapterMarkers,
      );
    }
  }

  void _playPause() {
    final isFinished = _latestValue.position >= _latestValue.duration && _latestValue.duration.inSeconds > 0;

    setState(() {
      if (controller.value.isPlaying) {
        notifier.hideStuff = false;
        _hideTimer?.cancel();
        controller.pause();
      } else {
        _cancelAndRestartTimer();

        if (!controller.value.isInitialized) {
          controller.initialize().then((_) {
            controller.play();
          });
        } else {
          if (isFinished) {
            controller.seekTo(Duration.zero);
          }
          controller.play();
        }
      }
    });
  }

  // These methods are used for both the skip and seek functionality
  void _seekRelative(Duration relativeSeek) {
    _cancelAndRestartTimer();
    final position = _latestValue.position + relativeSeek;
    final duration = _latestValue.duration;

    if (position < Duration.zero) {
      controller.seekTo(Duration.zero);
    } else if (position > duration) {
      controller.seekTo(duration);
    } else {
      controller.seekTo(position);
    }
  }

  void _seekBackward() {
    _seekRelative(const Duration(seconds: -10));
  }

  void _seekForward() {
    _seekRelative(const Duration(seconds: 10));
  }

  Future<void> _skipBack() async {
    _cancelAndRestartTimer();
    final beginning = Duration.zero.inMilliseconds;
    final skip = (_latestValue.position - const Duration(seconds: 15)).inMilliseconds;
    await controller.seekTo(Duration(milliseconds: math.max(skip, beginning)));
    // Restoring the video speed to selected speed
    // A delay of 1 second is added to ensure a smooth transition of speed after reversing the video as reversing is an asynchronous function
    Future.delayed(const Duration(milliseconds: 1000), () {
      controller.setPlaybackSpeed(selectedSpeed);
    });
  }

  Future<void> _skipForward() async {
    _cancelAndRestartTimer();
    final end = _latestValue.duration.inMilliseconds;
    final skip = (_latestValue.position + const Duration(seconds: 15)).inMilliseconds;
    await controller.seekTo(Duration(milliseconds: math.min(skip, end)));
    // Restoring the video speed to selexcted speed
    // A delay of 1 second is added to ensure a smooth transition of speed after forwarding the video as forwaring is an asynchronous function
    Future.delayed(const Duration(milliseconds: 1000), () {
      controller.setPlaybackSpeed(selectedSpeed);
    });
  }

  void _startHideTimer() {
    // Don't start hide timer in fullscreen if autoHideControlsInFullScreen is false
    if (chewieController.isFullScreen && !chewieController.autoHideControlsInFullScreen) {
      return;
    }

    final hideControlsTimer =
        chewieController.hideControlsTimer.isNegative ? ChewieController.defaultHideControlsTimer : chewieController.hideControlsTimer;
    _hideTimer = Timer(hideControlsTimer, () {
      setState(() {
        notifier.hideStuff = true;
      });
    });
  }

  void _bufferingTimerTimeout() {
    _displayBufferingIndicator = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _updateState() {
    if (!mounted) return;

    final bool buffering = getIsBuffering(controller);

    // display the progress bar indicator only after the buffering delay if it has been set
    if (chewieController.progressIndicatorDelay != null) {
      if (buffering) {
        _bufferingDisplayTimer ??= Timer(chewieController.progressIndicatorDelay!, _bufferingTimerTimeout);
      } else {
        _bufferingDisplayTimer?.cancel();
        _bufferingDisplayTimer = null;
        _displayBufferingIndicator = false;
      }
    } else {
      _displayBufferingIndicator = buffering;
    }

    setState(() {
      _latestValue = controller.value;
      _subtitlesPosition = controller.value.position;
    });
  }
}

class _PlaybackSpeedDialog extends StatelessWidget {
  const _PlaybackSpeedDialog({required List<double> speeds, required double selected}) : _speeds = speeds, _selected = selected;

  final List<double> _speeds;
  final double _selected;

  @override
  Widget build(BuildContext context) {
    final selectedColor = CupertinoTheme.of(context).primaryColor;

    return CupertinoActionSheet(
      actions:
          _speeds
              .map(
                (e) => CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.of(context).pop(e);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [if (e == _selected) Icon(Icons.check, size: 20.0, color: selectedColor), Text(e.toString())],
                  ),
                ),
              )
              .toList(),
    );
  }
}
