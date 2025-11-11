import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class ListingLocationPicker extends StatefulWidget {
  const ListingLocationPicker({
    super.key,
    this.initialLocation,
    required this.onChanged,
  });

  final LatLng? initialLocation;
  final ValueChanged<LatLng> onChanged;

  @override
  State<ListingLocationPicker> createState() => _ListingLocationPickerState();
}

class _ListingLocationPickerState extends State<ListingLocationPicker> {
  late final MapController _mapController;
  LatLng? _selected;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selected = widget.initialLocation;
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter =
        _selected ?? const LatLng(-22.9068, -43.1729); // Rio default
    final initialZoom = _selected != null ? 13.0 : 4.5;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: initialCenter,
                  initialZoom: initialZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  onTap: (tapPosition, point) {
                    setState(() {
                      _selected = point;
                    });
                    widget.onChanged(point);
                    _mapController.move(point, 15);
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'br.frota.zapnautico',
                  ),
                  if (_selected != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _selected!,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_pin,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _selected == null
                ? 'Toque no mapa para posicionar o anúncio.'
                : 'Local selecionado: ${_selected!.latitude.toStringAsFixed(4)}, ${_selected!.longitude.toStringAsFixed(4)}',
          ),
        ],
      ),
    );
  }
}
