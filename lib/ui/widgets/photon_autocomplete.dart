import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_photon/flutter_photon.dart';
import 'package:latlong2/latlong.dart';

import 'package:unustasis/service/location_polling.dart';
import 'package:unustasis/service/photon_service.dart';

/// Photon-backed place search field. Suggestions render in an overlay anchored
/// under the field so the calling layout does not have to reserve space.
class PhotonAutocomplete extends StatefulWidget {
  final void Function(PhotonFeature feature) onSelected;
  final String Function(PhotonFeature feature) formatFeature;
  final FocusNode? focusNode;
  final String? hintText;

  const PhotonAutocomplete({
    required this.onSelected,
    required this.formatFeature,
    this.focusNode,
    this.hintText,
    super.key,
  });

  @override
  State<PhotonAutocomplete> createState() => _PhotonAutocompleteState();
}

class _PhotonAutocompleteState extends State<PhotonAutocomplete> {
  Timer? _debounce;
  List<PhotonFeature> _suggestions = [];
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  LatLng? _lastOwnLocation;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    pollLocation().then((loc) {
      _lastOwnLocation = loc;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    // Only dispose the FocusNode if we created it internally
    if (widget.focusNode == null) _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else if (_suggestions.isNotEmpty) {
      _showOverlay();
    }
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.length < 3) {
      _removeOverlay();
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await photonForwardSearch(
          query,
          ownLocation: _lastOwnLocation,
        );
        if (mounted) {
          setState(() => _suggestions = results);
          if (results.isNotEmpty && _focusNode.hasFocus) {
            _showOverlay();
          } else {
            _removeOverlay();
          }
        }
      } catch (_) {
        // silently ignore search errors
      }
    });
  }

  void _showOverlay() {
    _removeOverlay();
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final feature = _suggestions[index];
                  return ListTile(
                    dense: true,
                    title: Text(widget.formatFeature(feature)),
                    onTap: () {
                      _controller.clear();
                      _removeOverlay();
                      _focusNode.unfocus();
                      setState(() => _suggestions = []);
                      widget.onSelected(feature);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        decoration: InputDecoration(
          hintText: widget.hintText ??
              FlutterI18n.translate(context, "nav_search_hint"),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    _removeOverlay();
                    setState(() => _suggestions = []);
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}