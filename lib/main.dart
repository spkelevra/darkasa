import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For System UI control
import 'package:permission_handler/permission_handler.dart';
import 'package:super_clipboard/super_clipboard.dart'; // For clipboard image support
import 'package:pro_image_editor/pro_image_editor.dart'; // Image Editor Package
import 'dart:io';
import 'dart:typed_data'; // Required for Uint8List


void main() {
  runApp(const DarkasaApp());
}


class DarkasaApp extends StatelessWidget {
  const DarkasaApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Darkasa',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const FloatingImageViewer(),
    );
  }
}


class FloatingImageViewer extends StatefulWidget {
  const FloatingImageViewer({super.key});


  @override
  State<FloatingImageViewer> createState() => _FloatingImageViewerState();
}


class _FloatingImageViewerState extends State<FloatingImageViewer> with TickerProviderStateMixin {
  List<String>? _imagePaths;
  int _currentIndex = 0;
  bool _isLoading = true;
  
  // Fullscreen state
  bool _isFullScreen = false;

  final PageController _pageController = PageController();
  
  // Key for the thumbnail ListView to control scrolling
  final ScrollController _thumbnailScrollController = ScrollController();


  @override
  void initState() {
    super.initState();
    
    // Configure System UI for full-screen immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ));


    _initApp();
  }


  Future<void> _initApp() async {
    setState(() => _isLoading = true);

    // Request "Manage All Files" permission for Android 10+
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      
      if (status.isGranted) {
        await _loadImagesFromStorage();
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permission denied. Cannot access storage.")),
        );
      }
    } else {
      // For iOS or older Android, use standard permissions
      var status = await [Permission.storage, Permission.photos].request();
      if (status[Permission.storage]!.isGranted || status[Permission.photos]!.isGranted) {
        await _loadImagesFromStorage();
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Permission denied. Cannot load images.")),
        );
      }
    }
  }


  Future<void> _loadImagesFromStorage() async {
    try {
      List<String> allPaths = [];

      final directories = [
        '/storage/emulated/0/DCIM/Camera',
        '/storage/emulated/0/Pictures',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Pictures/Darkasa', // Include Darkasa folder in scan
      ];

      for (String dirPath in directories) {
        Directory dir = Directory(dirPath);
        if (await dir.exists()) {
          await for (FileSystemEntity entity in dir.list(recursive: false)) {
            if (entity is File && _isImageFile(entity.path)) {
              allPaths.add(entity.path);
            }
          }
        }
      }

      // Sort by last modified date (newest first)
      allPaths.sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));

      if (allPaths.isNotEmpty) {
        setState(() {
          _imagePaths = allPaths;
          _currentIndex = 0;
          _isLoading = false;
        });
        
        // Scroll to first item after loading
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToCurrentIndex();
        });
      } else {
        setState(() => _isLoading = false);
      }

    } catch (e) {
      print("Error loading images: $e");
      setState(() => _isLoading = false);
    }
  }


  bool _isImageFile(String path) {
    final ext = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }


  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    
    // Scroll thumbnail bar to keep current image visible at the left
    if (!_isFullScreen) {
      Future.delayed(const Duration(milliseconds: 10), () {
        _scrollToCurrentIndex();
      });
    }
  }

  /// Scrolls the thumbnail list so the current index is aligned to the LEFT edge
  void _scrollToCurrentIndex() {
    if (!_thumbnailScrollController.hasClients) return;
    
    // Approx width of each thumbnail + padding (80 img + 10 total horizontal padding)
    final itemWidth = 90.0; 
    
    // Calculate target offset to place current index at the far left (x=0 relative to list start)
    final targetOffset = _currentIndex * itemWidth;
    
    // Clamp the offset to valid range so we don't scroll past ends
    final maxScroll = _thumbnailScrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);

    _thumbnailScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }


  /// Toggle Fullscreen Mode
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      
      // Update System UI based on fullscreen state
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ));
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ));
        
        // Scroll to current index after exiting fullscreen so it's visible at the left
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToCurrentIndex();
        });
      }
    });
  }


  /// Copies the image file to the system clipboard as raw PNG bytes.
  Future<void> _copyImageToClipboard(String imagePath) async {
    try {
      final File file = File(imagePath);
      
      if (!await file.exists()) {
        throw Exception("File not found");
      }

      // Read the image bytes
      List<int> imageBytesList = await file.readAsBytes();
      
      // Convert List<int> to Uint8List as required by super_clipboard
      final Uint8List imageBytes = Uint8List.fromList(imageBytesList);

      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        throw Exception("Clipboard API not supported on this platform.");
      }

      final item = DataWriterItem();
      
      // Add the image data as PNG. 
      item.add(Formats.png(imageBytes));

      await clipboard.write([item]);
      
    } catch (e) {
      print("Error copying image: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to copy image: ${e.toString()}")),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_imagePaths == null || _imagePaths!.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('darkasa')),
        body: const Center(
          child: Text('No images found or permission denied.', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final currentImagePath = _imagePaths![_currentIndex];
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // --- Main Page View (Handles Scrolling) ---
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _imagePaths!.length,
              itemBuilder: (context, index) {
                final path = _imagePaths![index];
                
                // If in fullscreen mode for this specific page, show zoomable image
                if (_isFullScreen && index == _currentIndex) {
                  return GestureDetector(
                    onTap: () => _toggleFullScreen(), // Single tap to exit
                    child: InteractiveImageWidget(imagePath: path),
                  );
                } else {
                  // Normal view with tap to enter fullscreen
                  return GestureDetector(
                    onTap: () {
                      if (!_isFullScreen) {
                        _toggleFullScreen();
                      }
                    },
                    onDoubleTap: () async {
                      await _copyImageToClipboard(path);
                      
                      if (mounted && !_isFullScreen) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Image copied to clipboard!"),
                            duration: Duration(seconds: 1),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    child: Center(
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  );
                }
              },
            ),
          ),

          // --- UI ELEMENTS (Hidden in Fullscreen) ---
          if (!_isFullScreen) ...[
            
            // --- EDIT BUTTON (Left side, above bottom bar) ---
            Positioned(
              bottom: 130 + bottomPadding, 
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white, size: 24),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ImageEditorScreen(imagePath: currentImagePath),
                      ),
                    );
                    
                    // Refresh image list if edit was successful AND saved to disk
                    if (result == true && mounted) {
                      await _loadImagesFromStorage();
                      
                      // Show success message
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Image saved to Darkasa folder & copied!"),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    } else if (result == 'clipboard' && mounted) {
                       // If result is 'clipboard', we just copied it but didn't save to disk
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(
                           content: Text("Edited image copied to clipboard!"),
                           backgroundColor: Colors.blue,
                           duration: Duration(seconds: 2),
                         ),
                       );
                    }
                  },
                ),
              ),
            ),

            // --- Bottom Strip & Controls Container ---
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                bottom: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The Strip (Thumbnails)
                    Container(
                      height: 100,
                      color: Colors.black.withOpacity(0.8),
                      child: ListView.builder(
                        controller: _thumbnailScrollController, // Added controller for scrolling
                        scrollDirection: Axis.horizontal,
                        itemCount: _imagePaths!.length,
                        itemBuilder: (context, index) {
                          final path = _imagePaths![index];
                          final isSelected = index == _currentIndex;
                          
                          return GestureDetector(
                            onTap: () {
                              _pageController.jumpToPage(index);
                            },
                            onDoubleTap: () async {
                              await _copyImageToClipboard(path);
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Image copied to clipboard!"),
                                    duration: Duration(seconds: 1),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.transparent,
                                    width: isSelected ? 3.0 : 0.0,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: Image.file(
                                  File(path),
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // --- Filename Label ---
            Positioned(
              bottom: 130 + bottomPadding, 
              left: 80,
              right: 20,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    File(currentImagePath).path.split('/').last,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _thumbnailScrollController.dispose();
    super.dispose();
  }
}

/// A simple interactive image widget that supports pinch-to-zoom and pan.
class InteractiveImageWidget extends StatefulWidget {
  final String imagePath;

  const InteractiveImageWidget({required this.imagePath});

  @override
  State<InteractiveImageWidget> createState() => _InteractiveImageWidgetState();
}

class _InteractiveImageWidgetState extends State<InteractiveImageWidget> with SingleTickerProviderStateMixin {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: (details) {},
      onScaleUpdate: (details) {
        setState(() {
          _scale = details.scale.clamp(1.0, 5.0); // Limit zoom between 1x and 5x
          
          if (_scale > 1.0) {
            // Apply pan only when zoomed in
            _offset += details.focalPointDelta;
          } else {
            // Reset offset when not zoomed
            _offset = Offset.zero;
          }
        });
      },
      onScaleEnd: (details) {
        if (_scale <= 1.0) {
           setState(() {
             _scale = 1.0;
             _offset = Offset.zero;
           });
        }
      },
      child: Center(
        child: Transform.scale(
          scale: _scale,
          child: Transform.translate(
            offset: _offset,
            child: Image.file(
              File(widget.imagePath),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }
}


// --- EDITOR SCREEN WIDGET (Full Editor) ---
class ImageEditorScreen extends StatefulWidget {
  final String imagePath;
  
  const ImageEditorScreen({required this.imagePath});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  
  // Flag to determine if we should save to disk or just clipboard
  bool _saveToDisk = false;

  Future<void> _handleSave(Uint8List bytes) async {
    try {
      final fileName = File(widget.imagePath).path.split('/').last;
      
      // 1. Copy to Clipboard (Always happens)
      try {
        final clipboard = SystemClipboard.instance;
        if (clipboard != null) {
          final item = DataWriterItem();
          item.add(Formats.png(bytes));
          await clipboard.write([item]);
        }
      } catch (e) {
        print("Warning: Clipboard failed: $e");
      }

      // 2. Save to Disk (Only if _saveToDisk is true)
      if (_saveToDisk) {
        final directory = Directory('/storage/emulated/0/Pictures/Darkasa');
        
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        
        final savePath = '${directory.path}/$fileName';
        final file = File(savePath);
        
        // Simple retry logic in case of transient permission issues
        try {
          await file.writeAsBytes(bytes);
        } catch (e) {
          print("First save attempt failed, retrying...");
          await Future.delayed(const Duration(milliseconds: 500));
          await file.writeAsBytes(bytes);
        }
        
        Navigator.pop(context, true); // Return true for disk save
      } else {
        Navigator.pop(context, 'clipboard'); // Return string for clipboard only
      }

    } catch (e) {
      Navigator.pop(context, false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Image"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Button to toggle Save to Disk option
          IconButton(
            icon: Icon(
              _saveToDisk ? Icons.save : Icons.save_outlined,
              color: _saveToDisk ? Colors.green : Colors.white70,
            ),
            tooltip: _saveToDisk ? "Save to Folder Enabled" : "Enable Save to Folder",
            onPressed: () {
              setState(() {
                _saveToDisk = !_saveToDisk;
              });
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_saveToDisk ? "Save to Folder Enabled" : "Save to Folder Disabled"),
                  duration: const Duration(seconds: 1),
                  backgroundColor: _saveToDisk ? Colors.green : Colors.grey,
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        child: ProImageEditor.file(
          File(widget.imagePath),
          
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (Uint8List bytes) async {
              // This is called when the user clicks the CHECKMARK inside the editor.
              await _handleSave(bytes);
            },
          ),
        ),
      ),
    );
  }
}
