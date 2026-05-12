class DlnaDevice {
  final String id;
  final String friendlyName;
  final String manufacturer;
  final String modelName;
  final Uri location;
  final Uri controlUrl;

  const DlnaDevice({
    required this.id,
    required this.friendlyName,
    required this.manufacturer,
    required this.modelName,
    required this.location,
    required this.controlUrl,
  });

  @override
  bool operator ==(Object other) =>
      other is DlnaDevice && other.id == id && other.controlUrl == controlUrl;

  @override
  int get hashCode => Object.hash(id, controlUrl);
}
