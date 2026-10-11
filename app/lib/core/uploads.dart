// Owned by AppWand. Files and images: pick, upload to POST /api/uploads, show.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'config.dart';
import 'i18n.dart';
import 'icons.dart';
import 'lists.dart' show Skeleton, SkeletonBox;
import 'plugins.g.dart';

class UploadedFile {
  const UploadedFile({required this.path, required this.url, required this.name, required this.size});

  /// What a column stores, e.g. "/uploads/1712345-ab12cd.png".
  final String path;
  final String url;
  final String name;
  final int size;

  factory UploadedFile.fromJson(Map<String, dynamic> json) => UploadedFile(
        path: '${json['path'] ?? ''}',
        url: '${json['url'] ?? ''}',
        name: '${json['name'] ?? ''}',
        size: num.tryParse('${json['size']}')?.toInt() ?? 0,
      );
}

const Set<String> _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'};

/// Whether a stored path looks like an image (sample data uses picsum.photos).
bool isImagePath(dynamic path) {
  final value = '${path ?? ''}'.toLowerCase().split(RegExp(r'[?#]')).first;
  if (value.contains('://picsum.photos/')) return true;
  final dot = value.lastIndexOf('.');
  return dot >= 0 && _imageExtensions.contains(value.substring(dot + 1));
}

/// The full URL of a stored path (or of a URL), null when empty.
String? fileUrl(dynamic path) {
  final value = '${path ?? ''}'.trim();
  if (value.isEmpty || value == 'null') return null;
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  final origin = apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return '$origin${value.startsWith('/') ? '' : '/'}$value';
}

/// An image from a stored path or a URL, kept on the device once loaded
/// (cached_network_image): a shimmering placeholder while it loads, a
/// tinted box with an icon when there is none or it can't be shown,
/// and a tap that opens it full screen (showImagePreview) unless [preview]
/// is false. Give it a width and height, or a parent that sizes it.
class AppImage extends StatelessWidget {
  const AppImage(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.circle = false,
    this.preview = true,
    this.title,
  });

  /// A stored path ("/uploads/...") or a full URL; null or empty shows the placeholder.
  final dynamic path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final bool circle;

  /// Whether a tap opens the image full screen.
  final bool preview;

  /// Shown above the full-screen image.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final url = fileUrl(path);
    Widget child = url == null
        ? const _ImageFallback(icon: AppIcons.image)
        : CachedNetworkImage(
            imageUrl: url,
            width: width,
            height: height,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 250),
            fadeOutDuration: const Duration(milliseconds: 150),
            placeholder: (context, url) => const Skeleton(child: SkeletonBox(height: null)),
            errorWidget: (context, url, error) => const _ImageFallback(icon: AppIcons.brokenImage),
          );
    child = SizedBox(width: width, height: height, child: child);
    if (circle) {
      child = ClipOval(child: child);
    } else if (radius > 0) {
      child = ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
    }
    if (url == null || !preview) return child;
    return Semantics(
      button: true,
      label: title ?? tr('View image'),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: () => showImagePreview(context, path, title: title), child: child),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: scheme.outline)),
    );
  }
}

/// Opens an image full screen over the app: pinch or scroll to zoom, drag to
/// move, double tap to zoom in and out. Close, Esc or Back leaves it.
Future<void> showImagePreview(BuildContext context, dynamic path, {String? title}) async {
  final url = fileUrl(path);
  if (url == null) return;
  await showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: tr('Close'),
    barrierColor: Colors.black.withAlpha(235),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) => _ImagePreview(url: url, title: title),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class _ImagePreview extends StatefulWidget {
  const _ImagePreview({required this.url, this.title});
  final String url;
  final String? title;

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  static const double _doubleTapScale = 2.5;

  final TransformationController _zoom = TransformationController();
  Offset _tapped = Offset.zero;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  // Zooms in on the point that was tapped, or back out to the whole image.
  void _toggleZoom() {
    if (_zoom.value.getMaxScaleOnAxis() > 1.01) {
      _zoom.value = Matrix4.identity();
      return;
    }
    _zoom.value = Matrix4.identity()
      ..setEntry(0, 0, _doubleTapScale)
      ..setEntry(1, 1, _doubleTapScale)
      ..setEntry(0, 3, -_tapped.dx * (_doubleTapScale - 1))
      ..setEntry(1, 3, -_tapped.dy * (_doubleTapScale - 1));
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.title ?? '').trim();
    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onDoubleTapDown: (details) => _tapped = details.localPosition,
            onDoubleTap: _toggleZoom,
            child: InteractiveViewer(
              transformationController: _zoom,
              minScale: 1,
              maxScale: 6,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.url,
                  fit: BoxFit.contain,
                  fadeInDuration: const Duration(milliseconds: 150),
                  progressIndicatorBuilder: (context, url, progress) =>
                      CircularProgressIndicator(color: Colors.white, value: progress.progress),
                  errorWidget: (context, url, error) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.brokenImage, color: Colors.white70, size: 48),
                      const SizedBox(height: 12),
                      Text(tr('This image can\'t be shown.'), style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Close'),
                style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(AppIcons.close),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The system file picker; null when the person cancels.
Future<PickedUpload?> pickFile({bool imagesOnly = false}) async {
  final picked = await FilePicker.platform.pickFiles(type: imagesOnly ? FileType.image : FileType.any, withData: true);
  final file = picked?.files.firstOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return (bytes: bytes, name: file.name);
}

/// Lets the person choose a file: a plugin's picker when one is added in
/// AppWand (the camera, image compression), else the system file picker.
Future<PickedUpload?> pickUpload(BuildContext context, {bool imagesOnly = false}) async {
  for (final plugin in appPlugins) {
    if (plugin.pickUpload != null) return plugin.pickUpload!(context, imagesOnly: imagesOnly);
  }
  return pickFile(imagesOnly: imagesOnly);
}

/// Lets the user choose a file and uploads it; null when they cancel.
Future<UploadedFile?> pickAndUpload(WidgetRef ref, {bool imagesOnly = false}) async {
  final file = await pickUpload(ref.context, imagesOnly: imagesOnly);
  if (file == null) return null;
  final data = await ref.read(apiClientProvider).upload('/uploads', bytes: file.bytes, filename: file.name);
  return UploadedFile.fromJson(Map<String, dynamic>.from(data as Map));
}

/// A form field for a file or image column: shows the current file, uploads
/// a new one, and hands back the stored path (null when removed).
class FileField extends ConsumerStatefulWidget {
  const FileField({
    super.key,
    this.value,
    required this.onChanged,
    this.label,
    this.imagesOnly = false,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  /// "File" (in the app's language) when not given.
  final String? label;
  final bool imagesOnly;

  @override
  ConsumerState<FileField> createState() => _FileFieldState();
}

class _FileFieldState extends ConsumerState<FileField> {
  bool _busy = false;
  String? _error;
  String? _name;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await pickAndUpload(ref, imagesOnly: widget.imagesOnly);
      if (file != null) {
        _name = file.name;
        widget.onChanged(file.path);
      }
    } catch (e) {
      _error = errorMessage(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = (widget.value ?? '').trim();
    final url = fileUrl(value);
    final showImage = url != null && (widget.imagesOnly || isImagePath(value));
    final label = widget.label ?? tr('File');
    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: _error),
      child: Row(children: [
        if (showImage) ...[
          AppImage(value, width: 56, height: 56, radius: 8, title: label),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            value.isEmpty ? tr('No file') : (_name ?? value.split('/').last),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          TextButton.icon(
            onPressed: _pick,
            icon: const Icon(AppIcons.upload),
            label: Text(value.isEmpty ? tr('Upload') : tr('Replace')),
          ),
          if (value.isNotEmpty)
            IconButton(
              tooltip: tr('Remove'),
              icon: const Icon(AppIcons.close),
              onPressed: () {
                setState(() => _name = null);
                widget.onChanged(null);
              },
            ),
        ],
      ]),
    );
  }
}
