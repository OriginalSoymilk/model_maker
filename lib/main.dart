import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/rendering.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pose Data Collection',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: VideoScreen(),
    );
  }
}

class VideoScreen extends StatefulWidget {
  @override
  _VideoScreenState createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  late VideoPlayerController _controller;
  final PoseDetector _poseDetector =
      PoseDetector(options: PoseDetectorOptions());
  List<Map<String, dynamic>> _csvData = [];
  bool _isDetecting = false;
  final GlobalKey _videoKey = GlobalKey();
  bool _isVideoLoaded = false;

  @override
  void initState() {
    super.initState();
    // 初始化视频控制器，但不加载视频
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(''), // 初始化空链接
    );
    _controller.addListener(_onVideoLoadStateChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoLoadStateChanged);
    _controller.dispose();
    super.dispose();
  }

  // 当视频加载状态发生变化时调用的方法
  void _onVideoLoadStateChanged() {
    if (_controller.value.isInitialized && !_isVideoLoaded) {
      // 当视频控制器初始化完成并且视频尚未加载时
      setState(() {
        _isVideoLoaded = true;
      });
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null) {
      _controller = VideoPlayerController.file(File(pickedFile.path))
        ..initialize().then((_) {
          setState(() {});
          _controller.play();
        });
    }
  }

  Future<ui.Image?> _captureFrame() async {
    try {
      final context = _videoKey.currentContext;
      if (context != null) {
        final RenderRepaintBoundary boundary =
            context.findRenderObject() as RenderRepaintBoundary;
        ui.Image image = await boundary.toImage(pixelRatio: 1.0);
        return image;
      } else {
        print("Error capturing frame: RenderRepaintBoundary context is null");
      }
    } catch (e) {
      print("Error capturing frame: $e");
    }
    return null;
  }

  Future<void> _recordPose(String label) async {
    print(label);
    if (_isDetecting) return;
    _isDetecting = true;

    final ui.Image? image = await _captureFrame();
    if (image != null) {
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final Uint8List bytes = byteData.buffer.asUint8List();
        final tempDir = await getTemporaryDirectory();
        final file =
            await File('${tempDir.path}/frame.png').writeAsBytes(bytes);
        final inputImage = InputImage.fromFilePath(file.path);

        try {
          final List<Pose> detectedPoses =
              await _poseDetector.processImage(inputImage);

          if (detectedPoses.isNotEmpty) {
            for (var pose in detectedPoses) {
              final Map<String, dynamic> poseMap = {
                'label': label,
              };

              for (var landmark in pose.landmarks.values) {
                final Map<String, dynamic> landmarkMap = {
                  "x": landmark.x.toStringAsFixed(2),
                  "y": landmark.y.toStringAsFixed(2),
                  "z": landmark.z.toStringAsFixed(2),
                  "v": landmark.type,
                };
                poseMap[landmark.type.toString()] = landmarkMap;
              }
              print(poseMap);
              _csvData.add(poseMap);
            }
          }
        } catch (e) {
          print("Error detecting pose: $e");
        } finally {
          _isDetecting = false;
        }
      }
    } else {
      print('image = null');
    }
  }

//修改後的代碼

  Future<String> _getFilePath() async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String filePath = '${appDocDir.path}/pose_data.csv';
    return filePath;
  }

  void _saveData() async {
    // 获取当前的上下文
    BuildContext? context = _videoKey.currentContext;

    // 如果上下文不为空，则显示对话框
    if (context != null) {
      String csv = const ListToCsvConverter()
          .convert(_csvData.map((map) => map.values.toList()).toList());
      final String filePath = await _getFilePath();
      final File file = File(filePath);
      await file.writeAsString(csv);
      print('Data saved to: $filePath');

      // 显示对话框
      // ignore: use_build_context_synchronously
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Success'),
            content: Text('Data saved to: $filePath'),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('OK'),
              ),
            ],
          );
        },
      );
    } else {
      print('Failed to show dialog: context is null');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pose Data Collection')),
      body: Column(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () => _recordPose('pose_a'),
                child: Text('Pose A'),
              ),
              ElevatedButton(
                onPressed: () => _recordPose('pose_b'),
                child: Text('Pose B'),
              ),
              // 添加更多動作按鈕...
            ],
          ),
          ElevatedButton(
            onPressed: _saveData,
            child: Text('Save Data'),
          ),
          ElevatedButton(
            onPressed: _pickVideo,
            child: Text('Select Video'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying
                ? _controller.pause()
                : _controller.play();
          });
        },
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
        ),
      ),
    );
  }
}
