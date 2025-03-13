
class UsbDeviceInfo {
  final int busNumber;
  final int deviceAddress;
  final int vendorId;
  final int productId;
  final int deviceClass;
  final int deviceSubClass;
  final int deviceProtocol;
  final String? manufacturer;
  final String? product;
  final String? serialNumber;

  UsbDeviceInfo({
    required this.busNumber,
    required this.deviceAddress,
    required this.vendorId,
    required this.productId,
    required this.deviceClass,
    required this.deviceSubClass,
    required this.deviceProtocol,
    this.manufacturer,
    this.product,
    this.serialNumber,
  });

  @override
  String toString() {
    return 'UsbDeviceInfo( '
        'bus: $busNumber, '
        'address: $deviceAddress, '
        'vendorId: 0x${vendorId.toRadixString(16).padLeft(4, '0')}, '
        'productId: 0x${productId.toRadixString(16).padLeft(4, '0')}, '
        'class: 0x${deviceClass.toRadixString(16).padLeft(2, '0')}, '
        'subclass: 0x${deviceSubClass.toRadixString(16).padLeft(2, '0')}, '
        'protocol: 0x${deviceProtocol.toRadixString(16).padLeft(2, '0')}, '
        'manufacturer: $manufacturer, '
        'product: $product, '
        'serialNumber: $serialNumber)';
  }
}