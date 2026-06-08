import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For System UI control
import 'package:permission_handler/permission_handler.dart';
import 'package:super_clipboard/super_clipboard.dart'; // For clipboard image support
import 'package:pro_image_editor/pro_image_editor.dart'; // Image Editor Package
import 'dart:async';
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
        // Configure SnackBar globally to appear at the top and use bright grey text
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating, // Makes it float (allows top positioning logic in some contexts, but primarily styling)
          backgroundColor: Color(0xFF2C2C2C), // Dark Grey background for contrast
          contentTextStyle: TextStyle(color: Colors.white70), // Brighter Grey Text
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
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

    // Request "Manage All Files" permission.
    // On Android 11+, this redirects to Settings if not granted.
    // On older Android, it requests standard storage permissions.
    var status = await Permission.manageExternalStorage.request();

    print("DEBUG: Manage External Storage Status: $status");

    if (status.isGranted) {
      await _loadImagesFromStorage();
    } else {
      setState(() => _isLoading = false);
      
      // Show notification that permission is needed
      showTopNotification("Permission denied. Please enable 'All Files' access in Settings.", isError: true);

      // Redirect to App Settings so the user can manually grant permissions
      await openAppSettings();
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
        
        // Check if directory exists and is accessible
        bool exists = await dir.exists();
        print("DEBUG: Dir $dirPath exists? $exists");
        
        if (exists) {
          try {
            await for (FileSystemEntity entity in dir.list(recursive: false)) {
              if (entity is File && _isImageFile(entity.path)) {
                allPaths.add(entity.path);
              }
            }
          } catch (e) {
             print("DEBUG: Error listing $dirPath: $e");
          }
        }
      }

      // Sort by last modified date (newest first)
      allPaths.sort((a, b) => File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));

      if (allPaths.isNotEmpty) {
        setState(() {
          _imagePaths = allPaths;
          // Try to keep the current index if it's still valid, otherwise reset to 0
          if (_currentIndex >= allPaths.length) {
            _currentIndex = 0;
          }
          _isLoading = false;
        });
        
        // Scroll to first item after loading
        Future.delayed(const Duration(milliseconds: 100), () {
          _scrollToCurrentIndex();
        });
      } else {
        print("DEBUG: No images found in scanned directories.");
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
        showTopNotification("Failed to copy image: ${e.toString()}", isError: true);
      }
    }
  }

  /// Pastes an image from the system clipboard and saves it to the Darkasa folder.
  Future<void> _pasteImageFromClipboard() async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        showTopNotification("Clipboard API not supported on this device.", isError: true);
        return;
      }

      final reader = await clipboard.read();
      if (reader.items.isEmpty) {
        showTopNotification("No data found in clipboard.", isError: true);
        return;
      }

      // Try to find an image in the clipboard, checking multiple formats.
      // getFile() uses a callback pattern — wrap it with Completer so we can await.
      final imageFormats = [
        (Formats.png, 'png'),
        (Formats.jpeg, 'jpg'),
        (Formats.gif, 'gif'),
        (Formats.webp, 'webp'),
        (Formats.bmp, 'bmp'),
      ];

      Uint8List? imageBytes;
      String extension = 'png';

      for (final entry in imageFormats) {
        final format = entry.$1;
        final ext = entry.$2;

        if (!reader.canProvide(format)) continue;

        // Wrap the callback-based getFile() into an awaitable Future
        final completer = Completer<void>();
        reader.getFile(
          format,
          (DataReaderFile file) async {
            try {
              imageBytes = await file.readAll();
              extension = ext;
            } catch (e) {
              print("Error reading clipboard file: $e");
            } finally {
              if (!completer.isCompleted) completer.complete();
            }
          },
          onError: (error) {
            print("Clipboard getFile error: $error");
            if (!completer.isCompleted) completer.completeError(error);
          },
        );

        // Wait for the callback to fire with a timeout
        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            print("Clipboard read timed out for format $ext");
            throw TimeoutException('Clipboard read timed out');
          },
        );

        if (imageBytes != null && imageBytes!.isNotEmpty) break;
      }

      if (imageBytes == null || imageBytes!.isEmpty) {
        // Debug: log available formats to help diagnose
        final allFormats = reader.getFormats(Formats.standardFormats);
        print("Available clipboard formats: ${allFormats.map((f) => f.toString()).join(', ')}");
        showTopNotification("No image found in clipboard. Copy an image first, then try again.", isError: true);
        return;
      }

      // Generate a timestamped filename
      final now = DateTime.now();
      final timestamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'pasted_${timestamp}.$extension';

      // Ensure the Darkasa directory exists
      final directory = Directory('/storage/emulated/0/Pictures/Darkasa');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Save the file
      final savePath = '${directory.path}/$fileName';
      final file = File(savePath);
      await file.writeAsBytes(imageBytes!);

      // Refresh the image list to show the new image
      await _loadImagesFromStorage();

      if (mounted) {
        showTopNotification("Image saved as $fileName");
      }

    } catch (e) {
      print("Error pasting from clipboard: $e");
      if (mounted) {
        showTopNotification("Failed to paste image: ${e.toString()}", isError: true);
      }
    }
  }

  // Helper method to show notifications at the top
  void showTopNotification(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16, // Below status bar
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          elevation: 4.0,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              // Use a slightly lighter dark grey for better contrast with white70 text
              color: isError ? Colors.red.withOpacity(0.9) : const Color(0xFF333333), 
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12, width: 1),
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white70, // BRIGHTER GREY TEXT
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    // Remove after delay
    Future.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
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
                        showTopNotification("Image copied to clipboard!");
                      }
                    },
                    child: Center(
                      child: Image.file(
                        File(path),
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        key: ValueKey(path), // CRITICAL: Forces rebuild when path/content changes
                      ),
                    ),
                  );
                }
              },
            ),
          ),

          // --- UI ELEMENTS (Hidden in Fullscreen) ---
          if (!_isFullScreen) ...[
            
            // --- ACTION BUTTONS ROW (Edit, Refresh, Paste) ---
            Positioned(
              bottom: 130 + bottomPadding, 
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Edit button
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white, size: 24),
                      tooltip: 'Edit',
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ImageEditorScreen(imagePath: currentImagePath),
                          ),
                        );
                        
                        // Refresh image list if edit was successful AND saved to disk
                        if (result == true && mounted) {
                          // Force a refresh of the image list
                          await _loadImagesFromStorage();
                          
                          // Show success message at top
                          showTopNotification("Image saved to Darkasa folder & copied!");
                        } else if (result == 'clipboard' && mounted) {
                           // If result is 'clipboard', we just copied it but didn't save to disk
                           showTopNotification("Edited image copied to clipboard!");
                        }
                      },
                    ),
                    // Refresh button
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white, size: 24),
                      tooltip: 'Refresh',
                      onPressed: () async {
                        await _loadImagesFromStorage();
                        if (mounted) {
                          showTopNotification("Image list refreshed");
                        }
                      },
                    ),
                    // Paste from clipboard button
                    IconButton(
                      icon: const Icon(Icons.paste, color: Colors.white, size: 24),
                      tooltip: 'Paste & Save',
                      onPressed: () async {
                        await _pasteImageFromClipboard();
                      },
                    ),
                  ],
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
                                showTopNotification("Image copied to clipboard!");
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
                                  key: ValueKey(path), // CRITICAL: Forces rebuild when path/content changes
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
        
        // Direct write is now reliable with Manage All Files permission
        await file.writeAsBytes(bytes);
        
        Navigator.pop(context, true); // Return true for disk save
      } else {
        Navigator.pop(context, 'clipboard'); // Return string for clipboard only
      }

    } catch (e) {
      Navigator.pop(context, false);
      if (context.mounted) {
        // This SnackBar will now appear at the TOP due to MaterialApp theme settings
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save: $e"), 
            duration: const Duration(seconds: 3),
          ),
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
              
              // This SnackBar will now appear at the TOP due to MaterialApp theme settings
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_saveToDisk ? "Save to Folder Enabled" : "Save to Folder Disabled"),
                  duration: const Duration(seconds: 1),
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
