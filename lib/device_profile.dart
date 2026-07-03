enum DeviceModel { x4, x3 }

class DeviceProfile {
  final String name;
  final int width;
  final int height;
  final double previewWidth;
  final double previewHeight;

  const DeviceProfile({
    required this.name,
    required this.width,
    required this.height,
    required this.previewWidth,
    required this.previewHeight,
  });
}

const Map<DeviceModel, DeviceProfile> deviceProfiles = {
  DeviceModel.x4: DeviceProfile(
    name: 'Xteink X4',
    width: 480,
    height: 800,
    previewWidth: 210.0,
    previewHeight: 350.0,
  ),
  DeviceModel.x3: DeviceProfile(
    name: 'Xteink X3',
    width: 528,
    height: 792,
    previewWidth: 220.0,
    previewHeight: 330.0,
  ),
};