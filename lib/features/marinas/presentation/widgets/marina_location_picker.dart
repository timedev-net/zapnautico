import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MarinaLocationPicker extends StatefulWidget {
  const MarinaLocationPicker({
    super.key,
    this.initialLocation,
    required this.onChanged,
  });

  final LatLng? initialLocation;
  final ValueChanged<LatLng> onChanged;

  @override
  State<MarinaLocationPicker> createState() => _MarinaLocationPickerState();
}

class _MarinaLocationPickerState extends State<MarinaLocationPicker> {
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
    final theme = Theme.of(context);
    final initialCenter = _selected ?? const LatLng(-22.9068, -43.1729); // Rio de Janeiro default
    final initialZoom = _selected != null ? 14.0 : 4.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
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
                          Icons.location_on,
                          color: Colors.red,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _selected != null
              ? 'Localização selecionada: ${_selected!.latitude.toStringAsFixed(5)}, ${_selected!.longitude.toStringAsFixed(5)}'
              : 'Toque no mapa para marcar a localização da marina.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

