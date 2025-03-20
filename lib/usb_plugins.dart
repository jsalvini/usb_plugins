// ignore_for_file: constant_identifier_names

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:usb_plugins_printer/usb_device_info.dart';
import 'libusb_bindings_generated.dart';

class UsbPlugin {
  late UsbPluginsBindings _bindings;

  // Constructor that loads the native library
  UsbPlugin() {
    // Determine the library path based on the platform
    final DynamicLibrary library = _loadLibrary();
    // Initialize the bindings with the loaded library
    _bindings = UsbPluginsBindings(library);
  }

  // Load the native library based on the platform
  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libusb-1.0.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('libusb-1.0.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libusb-1.0.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libusb-1.0.dylib');
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  // Initialize the USB library
  int initUsbLibrary() {
    return _bindings.libusb_init(nullptr);
  }

  // Exit the USB library
  void exitUsbLibrary() {
    _bindings.libusb_exit(nullptr);
  }

  // Method to get detailed device information
  List<UsbDeviceInfo> getDetailedDeviceList() {
    final deviceListPtr = calloc<Pointer<Pointer<libusb_device>>>();
    final count = _bindings.libusb_get_device_list(nullptr, deviceListPtr);

    List<UsbDeviceInfo> deviceInfoList = [];

    if (count > 0) {
      final deviceList = deviceListPtr.value;

      for (int i = 0; i < count; i++) {
        final device = deviceList[i];

        // Get device descriptor
        final deviceDescriptor = calloc<libusb_device_descriptor>();
        _bindings.libusb_get_device_descriptor(device, deviceDescriptor);

        // Get bus number and device address
        final busNumber = _bindings.libusb_get_bus_number(device);
        final deviceAddress = _bindings.libusb_get_device_address(device);

        // Try to open the device to get string information
        String? manufacturer;
        String? product;
        String? serialNumber;

        // Create a pointer for the device handle
        final handlePtr = calloc<Pointer<libusb_device_handle>>();

        // Try to open the device
        final result = _bindings.libusb_open(device, handlePtr);
        if (result != 0) {
          log("Error opening device: $result");
        } else {
          // Get the device handle
          final handle = handlePtr.value;
          log("Device opened successfully. ProductId: ${deviceDescriptor.ref.idProduct} - VendorId: ${deviceDescriptor.ref.idVendor}");
          // Read strings if available
          if (deviceDescriptor.ref.iManufacturer > 0) {
            manufacturer = _getStringDescriptor(
                handle, deviceDescriptor.ref.iManufacturer);
            //log("Manufacturer: $manufacturer");
          } else {
            //log("Device does not provide a manufacturer descriptor.");
          }

          if (deviceDescriptor.ref.iProduct > 0) {
            product =
                _getStringDescriptor(handle, deviceDescriptor.ref.iProduct);
          }

          if (deviceDescriptor.ref.iSerialNumber > 0) {
            serialNumber = _getStringDescriptor(
                handle, deviceDescriptor.ref.iSerialNumber);
          }

          // Close the device
          _bindings.libusb_close(handle);
        }

        // Free the handle pointer
        calloc.free(handlePtr);

        // Create an object with the device information
        final deviceInfo = UsbDeviceInfo(
          busNumber: busNumber,
          deviceAddress: deviceAddress,
          vendorId: deviceDescriptor.ref.idVendor,
          productId: deviceDescriptor.ref.idProduct,
          deviceClass: deviceDescriptor.ref.bDeviceClass,
          deviceSubClass: deviceDescriptor.ref.bDeviceSubClass,
          deviceProtocol: deviceDescriptor.ref.bDeviceProtocol,
          manufacturer: manufacturer,
          product: product,
          serialNumber: serialNumber,
        );

        log('Adding device: $deviceInfo');

        deviceInfoList.add(deviceInfo);

        // Free the device descriptor
        calloc.free(deviceDescriptor);
      }

      // Free the device list
      _bindings.libusb_free_device_list(deviceList, 1);
    }

    // Free the device list pointer
    calloc.free(deviceListPtr);
    return deviceInfoList;
  }

  // Helper method to get string descriptors
  String ? _getStringDescriptor(
      Pointer<libusb_device_handle> handle, int index) {
    if (index == 0) {
      return null;
    } // If the index is 0, the device does not have this string
    final buffer = calloc<Uint8>(256);

    try {
      final length = _bindings.libusb_get_string_descriptor_ascii(
          handle, index, buffer.cast<UnsignedChar>(), 256);

      if (length > 0) {
        return String.fromCharCodes(buffer.asTypedList(length));
      } else {
        log("Error obtaining string descriptor with index $index. Error code: $length");
        return null;
      }
    } finally {
      calloc.free(buffer);
    }
  }

  // Methods to open and close devices
  Pointer<libusb_device_handle>? openDevice(int vendorId, int productId) {
    final handle =
        _bindings.libusb_open_device_with_vid_pid(nullptr, vendorId, productId);

    if (handle == nullptr) {
      return null;
    }

    return handle;
  }

  void closeDevice(Pointer<libusb_device_handle> handle) {
    _bindings.libusb_close(handle);
  }

  // Control transfer method
  int controlTransfer(
      Pointer<libusb_device_handle> handle,
      int requestType,
      int request,
      int value,
      int index,
      Pointer<UnsignedChar> data,
      int length,
      int timeout) {
    return _bindings.libusb_control_transfer(
        handle, requestType, request, value, index, data, length, timeout);
  }

  // Method to get additional device details
  Map<String, dynamic> getDeviceDetails(int vendorId, int productId) {
    final handle = openDevice(vendorId, productId);
    if (handle == null) {
      return {'error': 'Could not open device'};
    }

    try {
      final configDescriptor = calloc<Pointer<libusb_config_descriptor>>();

      // Get the active configuration descriptor
      final result = _bindings.libusb_get_active_config_descriptor(
          nullptr, configDescriptor);

      if (result < 0) {
        return {
          'error': 'Could not obtain configuration descriptor',
          'errorCode': result
        };
      }

      final config = configDescriptor.value;

      // Extract interface and endpoint information
      List<Map<String, dynamic>> interfaces = [];

      // Print available fields for debugging
      log("Available fields in config.ref: ${config.ref.toString()}");

      final numInterfaces = config.ref.bNumInterfaces;
      log("Number of interfaces: $numInterfaces");

      for (int i = 0; i < numInterfaces; i++) {
        final interfaceNumber = _bindings.libusb_claim_interface(handle, i);

        Map<String, dynamic> interfaceInfo = {
          'interfaceNumber': interfaceNumber,
          'endpoints': <Map<String, dynamic>>[]
        };

        interfaces.add(interfaceInfo);
      }

      // Free resources
      _bindings.libusb_free_config_descriptor(config);

      return {
        'configValue': config.ref.bConfigurationValue,
        'maxPower': config.ref.MaxPower,
        'selfPowered': (config.ref.bmAttributes & 0x40) != 0,
        'remoteWakeup': (config.ref.bmAttributes & 0x20) != 0,
        'numInterfaces': numInterfaces,
        'interfaces': interfaces,
        'note':
            'Interface information limited due to generated structure'
      };
    } catch (e) {
      return {
        'error': 'Error obtaining device details',
        'message': e.toString()
      };
    } finally {
      closeDevice(handle);
    }
  }

  // Corrected version that properly handles potentially null pointers
  // Modified method that allows both sending and receiving data
  Future<Map<String, dynamic>> sendDataToPrinter(
    int vendorId,
    int productId,
    Uint8List data, {
    int interfaceNumber = 0,
    int endpointAddress = 0x01,
    int readEndpointAddress = 0x81,
    int timeout = 10000,
    bool expectResponse = false,
    int maxResponseLength = 256,
  }) async {
    final Pointer<libusb_device_handle>? handleNullable =
        openDevice(vendorId, productId);
    if (handleNullable == nullptr || handleNullable == null) {
      return {'success': false, 'error': 'Could not open device'};
    }

    final handle = handleNullable;

    try {
      int hasKernelDriver = 0;
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          hasKernelDriver =
              _bindings.libusb_kernel_driver_active(handle, interfaceNumber);
          if (hasKernelDriver == 1) {
            log("Detaching kernel driver...");
            final detachResult =
                _bindings.libusb_detach_kernel_driver(handle, interfaceNumber);
            if (detachResult < 0) {
              log("Could not detach kernel driver: $detachResult");
            } else {
              log("Kernel driver detached successfully");
            }
          }
        } catch (e) {
          log("Error checking/detaching kernel driver: $e");
        }
      }

      final configResult = _bindings.libusb_set_configuration(handle, 1);
      if (configResult < 0) {
        log("Warning: Could not set configuration: $configResult");
      }

      int claimResult = -1;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts) {
        claimResult = _bindings.libusb_claim_interface(handle, interfaceNumber);
        if (claimResult == 0) break;

        log("Attempt ${attempts + 1} failed with error $claimResult. Retrying...");
        await Future.delayed(Duration(milliseconds: 500));
        attempts++;
      }

      if (claimResult < 0) {
        return {
          'success': false,
          'error':
              'Could not claim interface after $maxAttempts attempts',
          'errorCode': claimResult,
          'errorDescription': _getUsbErrorDescription(claimResult)
        };
      }

      final buffer = calloc<Uint8>(data.length);
      final bufferList = buffer.asTypedList(data.length);
      bufferList.setAll(0, data);

      final transferredPtr = calloc<Int>();

      log("Sending ${data.length} bytes to endpoint $endpointAddress...");
      int transferResult = _bindings.libusb_bulk_transfer(
          handle,
          endpointAddress,
          buffer.cast<UnsignedChar>(),
          data.length,
          transferredPtr,
          timeout);

      await Future.delayed(Duration(milliseconds: 5000));

      final bytesSent = transferredPtr.value;

      calloc.free(buffer);
      calloc.free(transferredPtr);

      if (transferResult < 0) {
        return {
          'success': false,
          'error': 'Error in data transfer',
          'errorCode': transferResult,
          'errorDescription': _getUsbErrorDescription(transferResult)
        };
      }

      log("Transfer successful: $bytesSent bytes sent");

      Map<String, dynamic> result = {
        'success': true,
        'bytesSent': bytesSent,
      };

      if (expectResponse) {
        final responseBuffer = calloc<Uint8>(maxResponseLength);
        final responseTransferredPtr = calloc<Int>();

        await Future.delayed(Duration(milliseconds: 800));

        log("Reading response from endpoint $readEndpointAddress...");
        final responseResult = _bindings.libusb_bulk_transfer(
            handle,
            readEndpointAddress,
            responseBuffer.cast<UnsignedChar>(),
            maxResponseLength,
            responseTransferredPtr,
            timeout);

        await Future.delayed(Duration(milliseconds: 100));

        if (responseResult >= 0) {
          final bytesReceived = responseTransferredPtr.value;
          log("Response received: $bytesReceived bytes");

          if (bytesReceived > 0) {
            final responseList = List<int>.filled(bytesReceived, 0);
            for (var i = 0; i < bytesReceived; i++) {
              responseList[i] = responseBuffer[i];
            }

            result['responseData'] = responseList;
            result['bytesReceived'] = bytesReceived;
          } else {
            result['responseData'] = [];
            result['bytesReceived'] = 0;
          }
        } else {
          log("Error reading response: $responseResult");
          result['responseError'] = _getUsbErrorDescription(responseResult);
        }

        calloc.free(responseBuffer);
        calloc.free(responseTransferredPtr);
      }

      _bindings.libusb_release_interface(handle, interfaceNumber);

      if (hasKernelDriver == 1 && (Platform.isLinux || Platform.isMacOS)) {
        _bindings.libusb_attach_kernel_driver(handle, interfaceNumber);
      }

      return result;
    } catch (e) {
      return {
        'success': false,
        'error': 'Error communicating with the printer',
        'exception': e.toString()
      };
    } finally {
      closeDevice(handle);
    }
  }

  Future<Map<String, dynamic>> detectPrinterConfiguration(
      int vendorId, int productId) async {
    final Pointer<libusb_device_handle>? handleNullable =
        openDevice(vendorId, productId);
    if (handleNullable == nullptr || handleNullable == null) {
      return {'success': false, 'error': 'Could not open device'};
    }

    final handle = handleNullable;

    try {
      final device = _bindings.libusb_get_device(handle);

      final deviceDescriptor = calloc<libusb_device_descriptor>();
      final descResult =
          _bindings.libusb_get_device_descriptor(device, deviceDescriptor);
      if (descResult < 0
        ) {
        calloc.free(deviceDescriptor);
        return {
          'success': false,
          'error': 'Could not obtain device descriptor',
          'errorCode': descResult
        };
      }

      final configDescPtr = calloc<Pointer<libusb_config_descriptor>>();
      final configResult =
          _bindings.libusb_get_active_config_descriptor(device, configDescPtr);
      if (configResult < 0) {
        calloc.free(deviceDescriptor);
        calloc.free(configDescPtr);
        return {
          'success': false,
          'error': 'Could not obtain configuration descriptor',
          'errorCode': configResult
        };
      }

      final config = configDescPtr.value;
      final numInterfaces = config.ref.bNumInterfaces;

      Map<String, dynamic> deviceInfo = {
        'vendorId': deviceDescriptor.ref.idVendor,
        'productId': deviceDescriptor.ref.idProduct,
        'deviceClass': deviceDescriptor.ref.bDeviceClass,
        'deviceSubClass': deviceDescriptor.ref.bDeviceSubClass,
        'deviceProtocol': deviceDescriptor.ref.bDeviceProtocol,
        'busNumber': _bindings.libusb_get_bus_number(device),
        'deviceAddress': _bindings.libusb_get_device_address(device),
        'numInterfaces': numInterfaces,
        'interfaces': <Map<String, dynamic>>[]
      };

      for (int i = 0; i < numInterfaces; i++) {
        if (Platform.isLinux || Platform.isMacOS) {
          try {
            final hasKernelDriver =
                _bindings.libusb_kernel_driver_active(handle, i);
            if (hasKernelDriver == 1) {
              _bindings.libusb_detach_kernel_driver(handle, i);
            }
          } catch (e) {
            log("Error checking/detaching kernel driver for interface $i: $e");
          }
        }

        int claimResult = _bindings.libusb_claim_interface(handle, i);
        if (claimResult < 0) {
          log("Could not claim interface $i: $claimResult");
          continue;
        }

        Map<String, dynamic> interfaceInfo = {
          'number': i,
          'canClaim': true,
          'endpoints': <Map<String, dynamic>>[]
        };

        List<int> commonEndpoints = [0x01, 0x02, 0x03, 0x81, 0x82, 0x83];

        for (int epAddress in commonEndpoints) {
          bool isOutput = (epAddress & 0x80) == 0;

          interfaceInfo['endpoints'].add({
            'address': epAddress,
            'type': 'bulk',
            'direction': isOutput ? 'output' : 'input'
          });
        }

        _bindings.libusb_release_interface(handle, i);

        if (Platform.isLinux || Platform.isMacOS) {
          try {
            final hasKernelDriver =
                _bindings.libusb_kernel_driver_active(handle, i);
            if (hasKernelDriver == 1) {
              _bindings.libusb_attach_kernel_driver(handle, i);
            }
          } catch (e) {
            log("Error reconnecting kernel driver for interface $i: $e");
          }
        }

        deviceInfo['interfaces'].add(interfaceInfo);
      }

      _bindings.libusb_free_config_descriptor(config);
      calloc.free(configDescPtr);
      calloc.free(deviceDescriptor);

      return {
        'success': true,
        'deviceInfo': deviceInfo,
        'note':
            'The listed endpoints are common endpoints for printers and may not correspond exactly to the actual endpoints of the device.'
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Error detecting configuration',
        'exception': e.toString()
      };
    } finally {
      closeDevice(handle);
    }
  }

  Future<Map<String, dynamic>> findAndClaimValidInterface(
      Pointer<libusb_device_handle>? handleNullable) async {
    if (handleNullable == nullptr || handleNullable == null) {
      return {'success': false, 'error': 'Invalid handle'};
    }

    final handle = handleNullable;

    for (int interfaceNumber = 0; interfaceNumber < 5; interfaceNumber++) {
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          final hasKernelDriver =
              _bindings.libusb_kernel_driver_active(handle, interfaceNumber);
          if (hasKernelDriver == 1) {
            final detachResult =
                _bindings.libusb_detach_kernel_driver(handle, interfaceNumber);
            if (detachResult < 0) continue;
          }
        } catch (e) {
          continue;
        }
      }

      final claimResult =
          _bindings.libusb_claim_interface(handle, interfaceNumber);
      if (claimResult == 0) {
        return {'success': true, 'interfaceNumber': interfaceNumber};
      }

    }

    return {'success': false, 'error': 'No valid interface found'};
  }

  // Helper method to translate libusb error codes
  String _getUsbErrorDescription(int errorCode) {
    switch (errorCode) {
      case -1:
        return 'LIBUSB_ERROR_IO: I/O error';
      case -2:
        return 'LIBUSB_ERROR_INVALID_PARAM: Invalid parameter';
      case -3:
        return 'LIBUSB_ERROR_ACCESS: Access denied';
      case -4:
        return 'LIBUSB_ERROR_NO_DEVICE: Device not found';
      case -5:
        return 'LIBUSB_ERROR_NOT_FOUND: Entity not found';
      case -6:
        return 'LIBUSB_ERROR_BUSY: Resource busy';
      case -7:
        return 'LIBUSB_ERROR_TIMEOUT: Timeout';
      case -8:
        return 'LIBUSB_ERROR_OVERFLOW: Overflow';
      case -9:
        return 'LIBUSB_ERROR_PIPE: Broken pipe';
      case -10:
        return 'LIBUSB_ERROR_INTERRUPTED: Operation interrupted';
      case -11:
        return 'LIBUSB_ERROR_NO_MEM: Insufficient memory';
      case -12:
        return 'LIBUSB_ERROR_NOT_SUPPORTED: Operation not supported';
      case -99:
        return 'LIBUSB_ERROR_OTHER: Unknown error';
      default:
        return 'Unknown error code: $errorCode';
    }
  }

  // Specific method for ESC/POS printers
  /*Future<Map<String, dynamic>> printEscPos(
    int vendorId,
    int productId,
    List<int> commandBytes,
    {int timeout = 5000}) async {

  // Convert List<int> to Uint8List
  final data = Uint8List.fromList(commandBytes);

  // Send commands to the printer
  return await sendDataToPrinter(vendorId, productId, data, timeout: timeout);
}*/

  // Modified printEscPos method to allow receiving response if needed
  Future<Map<String, dynamic>> printEscPos(
    int vendorId,
    int productId,
    List<int> commandBytes, {
    int interfaceNumber = 0,
    int endpointAddress = 0x01,
    int readEndpointAddress = 0x81,
    int timeout = 5000,
    bool autoInitialize = false,
    bool autoCut = false,
    bool expectResponse = false,
  }) async {
    List<int> finalCommands = [];

    // If automatic initialization is requested, add initialization command at the beginning
    if (autoInitialize) {
      // ESC @ - Initialize printer
      finalCommands.addAll([0x1B, 0x40]);
    }

    // Add main commands sent as parameters
    finalCommands.addAll(commandBytes);

    // If automatic cut is requested, add cut command at the end
    if (autoCut) {
      // GS V - Cut paper (full mode)
      finalCommands.addAll([0x1D, 0x56, 0x00]);
    }

    // Convert List<int> to Uint8List
    final data = Uint8List.fromList(finalCommands);

    // Attempt to send with various endpoints if the default fails
    Map<String, dynamic> result = await sendDataToPrinter(
      vendorId,
      productId,
      data,
      interfaceNumber: interfaceNumber,
      endpointAddress: endpointAddress,
      readEndpointAddress: readEndpointAddress,
      timeout: timeout,
      expectResponse: expectResponse,
    );

    // If the operation failed, try with an alternative endpoint
    if (result['success'] == false &&
        result['error']?.contains('transfer') == true) {
      log("Trying with alternative endpoint 0x02...");
      result = await sendDataToPrinter(
        vendorId,
        productId,
        data,
        interfaceNumber: interfaceNumber,
        endpointAddress: 0x02,
        readEndpointAddress: readEndpointAddress,
        timeout: timeout,
        expectResponse: expectResponse,
      );
    }

    return result;
  }

  Future<Map<String, dynamic>> getPrinterStatus(
    int vendorId,
    int productId,
    List<int> command, {
    int interfaceNumber = 0,
    int endpointAddress = 0x01,
    int readEndpointAddress = 0x81,
    int timeout = 10000,
    bool expectResponse = false,
    int maxResponseLength = 542,
  }) async {
    // Open the device
    final Pointer<libusb_device_handle>? handleNullable =
        openDevice(vendorId, productId);
    if (handleNullable == nullptr || handleNullable == null) {
      return {
        'success': false,
        'error': 'Could not open device',
        'isConnected': false,
        'statusType': command.length >= 3 ? command[2] : 0
      };
    }

    // Convert from Pointer? to Pointer ```dart
    // now that we know it's not null
    final handle = handleNullable;

    Map<String, dynamic> statusInfo = {
      'success': false,
      'isConnected': false,
      'rawData': null,
      'statusType': command.length >= 3 ? command[2] : 0
    };
    try {
      // Check if there is an active kernel driver and detach if necessary
      int hasKernelDriver = 0;
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          hasKernelDriver =
              _bindings.libusb_kernel_driver_active(handle, interfaceNumber);
          if (hasKernelDriver == 1) {
            log("Detaching kernel driver...");
            final detachResult =
                _bindings.libusb_detach_kernel_driver(handle, interfaceNumber);
            if (detachResult < 0) {
              log("Could not detach kernel driver: $detachResult");
            } else {
              log("Kernel driver detached successfully");
            }
          }
        } catch (e) {
          log("Error checking/detaching kernel driver: $e");
        }
      }

      // Configure the device if necessary
      final configResult = _bindings.libusb_set_configuration(handle, 1);
      if (configResult < 0) {
        log("Warning: Could not set configuration: $configResult");
      }

      // Claim the interface with multiple attempts
      int claimResult = -1;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts) {
        claimResult = _bindings.libusb_claim_interface(handle, interfaceNumber);
        if (claimResult == 0) break;

        log("Attempt ${attempts + 1} failed with error $claimResult. Retrying...");
        await Future.delayed(Duration(milliseconds: 500));
        attempts++;
      }

      if (claimResult < 0) {
        return {
          'success': false,
          'error': 'Could not claim interface',
          'isConnected': false,
          'statusType': command.length >= 3 ? command[2] : 0
        };
      }

      final buffer = calloc<Uint8>(command.length);
      final bufferList = buffer.asTypedList(command.length);
      bufferList.setAll(0, command);

      final transferredPtr = calloc<Int>();

      log("Sending command $command...");
      int transferResult = _bindings.libusb_bulk_transfer(
          handle,
          endpointAddress,
          buffer.cast<UnsignedChar>(),
          command.length,
          transferredPtr,
          timeout);

      await Future.delayed(Duration(milliseconds: 100));

      calloc.free(buffer);
      calloc.free(transferredPtr);

      if (transferResult < 0) {
        String errorDescription = _getUsbErrorDescription(transferResult);
        return {
          'success': false,
          'error':
              'Error sending command: $command, detail: $errorDescription',
          'isConnected': false,
          'statusType': command.length >= 3 ? command[2] : 0
        };
      }

      Uint8List buffer2 = Uint8List(512);
      final Pointer<UnsignedChar> dataPointer =
          malloc.allocate<UnsignedChar>(buffer2.length);
      for (var i = 0; i < buffer2.length; i++) {
        dataPointer[i] = buffer[i];
      }

      final Pointer<Int> transferredPointer = malloc.allocate<Int>(1);
      transferredPointer.value = 0;

      // Call the function correctly
      int readResult = _bindings.libusb_bulk_transfer(
        handle, // libusb_device_handle*
        0x81, // unsigned char endpoint
        dataPointer, // unsigned char* data
        buffer2.length, // int length
        transferredPointer, // int* transferred
        timeout, // unsigned int timeout
      );

      // Read how many bytes were transferred
      int bytesReceived = transferredPointer.value;

      if (readResult == 0 && bytesReceived > 0) {
        // Copy the received data back to a Uint8List
        Uint8List receivedData = Uint8List(bytesReceived);
        for (var i = 0; i < bytesReceived; i++) {
          receivedData[i] = dataPointer[i];
        }

        // Determine what type of command it is based on the third byte
        int statusType = command.length >= 3 ? command[2] : 0;

        statusInfo['success'] = true;
        statusInfo['isConnected'] = true;
        statusInfo['rawData'] = receivedData;
        statusInfo['binaryResponse'] =
            receivedData[0].toRadixString(2).padLeft(8, '0');
        statusInfo['statusType'] = statusType;

        // Interpret the data based on the status type
        if (bytesReceived > 0) {
          switch
          (statusType) {
            case 1: // Printer status [0x10, 0x04, 0x01]
              statusInfo['isOnline'] = (receivedData[0] & (1 << 3)) == 0;
              statusInfo['cashDrawerOpen'] = (receivedData[0] & (1 << 2)) != 0;
              break;

            case 2: // Offline status [0x10, 0x04, 0x02]
              statusInfo['isCoverOpen'] = (receivedData[0] & (1 << 2)) != 0;
              statusInfo['isPaperFeedByButton'] =
                  (receivedData[0] & (1 << 3)) != 0;
              break;

            case 4: // Paper sensor status [0x10, 0x04, 0x04]
              bool bit2 = (receivedData[0] & (1 << 2)) != 0;
              bool bit3 = (receivedData[0] & (1 << 3)) != 0;
              bool bit5 = (receivedData[0] & (1 << 5)) != 0;
              bool bit6 = (receivedData[0] & (1 << 6)) != 0;

              statusInfo['paperStatus'] = {
                'paperNearEnd': bit2 || bit3,
                'paperEnd': bit5 || bit6,
                'paperPresent': !(bit5 || bit6),
                'paperAdequate': !(bit2 || bit3),
              };
              break;

            default:
              statusInfo['error'] = 'Unrecognized command type';
          }
        }
      } else {
        log("Error: ${_bindings.libusb_error_name(readResult)}");
        log("Description: ${_getUsbErrorDescription(readResult)}");
        statusInfo['error'] =
            'Error reading response: ${_bindings.libusb_error_name(readResult)}';
      }

      // Free memory
      malloc.free(dataPointer);
      malloc.free(transferredPointer);

      // Release the interface
      _bindings.libusb_release_interface(handle, interfaceNumber);

      // Reattach the kernel driver if it was detached
      if (hasKernelDriver == 1 && (Platform.isLinux || Platform.isMacOS)) {
        _bindings.libusb_attach_kernel_driver(handle, interfaceNumber);
      }
    } catch (e) {
      log('Exception: $e');
      return {
        'success': false,
        'error': 'Error communicating with the printer: ${e.toString()}',
        'isConnected': false,
        'statusType': command.length >= 3 ? command[2] : 0
      };
    } finally {
      closeDevice(handle);
    }
    return statusInfo;
  }

  /// Simple function to interpret the printer status byte for 3nStart RPT008
  void interpretPrinterStatus(int statusByte) {
    String bits = statusByte.toRadixString(2).padLeft(8, '0');

    log('\n==== PRINTER STATUS 3NSTART RPT008 ====');
    log('Received byte: 0x${statusByte.toRadixString(16).padLeft(2, "0")} ($statusByte)');
    log('Binary representation: $bits');

    bool error = (statusByte & 0x80) != 0; // Bit 7
    bool paperFeed = (statusByte & 0x40) != 0; // Bit 6
    bool coverOpen = (statusByte & 0x20) != 0; // Bit 5
    bool sensorBit = (statusByte & 0x10) != 0; // Bit 4 (model specific)
    bool offline = (statusByte & 0x08) != 0; // Bit 3
    bool drawer1 = (statusByte & 0x04) != 0; // Bit 2
    bool drawer2 = (statusByte & 0x02) != 0; // Bit 1

    log('\nInterpretation:');
    log('- Online/Offline status: ${offline ? "OFFLINE" : "ONLINE"}');
    log('- Cover: ${coverOpen ? "OPEN" : "CLOSED"}');
    log('- Error: ${error ? "YES" : "NO"}');
    log('- Drawer: ${(drawer1 || drawer2) ? "OPEN" : "CLOSED"}');
    log('- Manual feed: ${paperFeed ? "ACTIVE" : "INACTIVE"}');
    log('- Special sensor (bit 4): ${sensorBit ? "ACTIVE" : "INACTIVE"}');

    if (statusByte == 22) {
      log('\nSummary for 0x16 (22):');
      log('The printer is ONLINE, with the cover CLOSED and no errors.');
      log('The drawer appears to be OPEN (bits 1 and 2 activated).');
      log('Bit 4 is active, which could indicate a specific state of the paper sensor or another model-specific function.');
    }

    log('\nBit diagram:');
    log('+---+---+---+---+---+---+---+---+');
    log('| 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 | Position');
    log('+---+---+---+---+---+---+---+---+');
    log('| ${bits[0]} | ${bits[1]} | ${bits[2]} | ${bits[3]} | ${bits[4]} | ${bits[5]} | ${bits[6]} | ${bits[7]} | Value');
    log('+---+---+---+---+---+---+---+---+');
    log('| E | F | C | S | O | D1| D2| R | Meaning');
    log('+---+---+---+---+---+---+---+---+');
    log(' E=Error, F=Feed, C=Cover, S=Sensor, O=Offline, D=Drawer, R=Reserved');

    log('\n========================================');
  }

  /// Utility function to display the full status
  void printFullStatus(Map<String, dynamic> statusMap) {
    if (!statusMap['success']) {
      log('Error obtaining status: ${statusMap['error']}');
      return;
    }

    log('\n==== PRINTER STATUS 3NSTART RPT008 ====');

    if (statusMap.containsKey('printerStatus')) {
      final status = statusMap['printerStatus']['status'];
      log('\n-- GENERAL STATUS --');
      log('Drawer: ${status['drawer']}');
      log('Online: ${status['online'] ? 'Yes' : 'No'}');
      log('Cover open: ${status['coverOpen'] ? 'Yes' : 'No'}');
      log('Manual paper feed: ${status['paperFeed'] ? 'Active' : 'Inactive'}');
      log('Error: ${status['error'] ? 'Yes' : 'No'}');
      log('Received byte: ${status['rawByte']}');
    }

    if (statusMap.containsKey('offlineStatus')) {
      final status = statusMap['offlineStatus']['status'];
      log('\n-- OFFLINE STATUS --');
      log('Cover open: ${status['coverOpen'] ? 'Yes' : 'No'}');
      log('Feed button pressed: ${status['paperFeedStop'] ? 'Yes' : 'No'}');
      log('Error occurred: ${status['errorOccurred'] ? 'Yes' : 'No'}');
      log('Offline: ${status['offline'] ? 'Yes' : 'No'}');
      log('Auto-recoverable error: ${status['autoRecoverableError'] ? 'Yes' : 'No'}');
      log('Waiting to go online: ${status['waitingForOnline'] ? 'Yes' : 'No'}');
      log('Received byte: ${status['rawByte']}');
    }

    if (statusMap.containsKey('errorStatus')) {
      final status = statusMap['errorStatus']['status'];
      log('\n-- ERROR STATUS --');
      log('Mechanical error: ${status['mechanicalError'] ? 'Yes' : 'No'}');
      log('Auto-recoverable error: ${status['autoRecoverError'] ? 'Yes' : 'No'}');
      log('Non-recoverable error: ${status['notRecoverableError'] ? 'Yes' : 'No'}');
      log('Cutter error: ${status['autoRecoverableCutterError'] ? 'Yes' : 'No'}');
      log('Cover open: ${status['coverOpen'] ? 'Yes' : 'No'}');
      log('Out of paper: ${status['paperEmpty'] ? 'Yes' : 'No'}');
      log('Received byte: ${status['rawByte']}');
    }

    if (statusMap.containsKey('paperStatus')) {
      final status = statusMap['paperStatus']['status'];
      log('\n-- PAPER STATUS --');
      log('Paper near end: ${status['paperNearEnd'] ? 'Yes' : 'No'}');
      log('Out of paper: ${status['paperEmpty'] ? 'Yes' : 'No'}');
      log('Stopped due to paper near end: ${status['paperNearEndStop'] ? 'Yes' : 'No'}');
      log('Stopped due to out of paper: ${status['paperEmptyStop'] ? 'Yes' : 'No'}');
      log('Received byte: ${status['rawByte']}');
    }

    log('\n========================================');
  }

  /// Debugging function to analyze the status byte
  void analyzeStatusByte(int statusByte) {
    String bits = statusByte.toRadixString(2).padLeft(8, "0");
    log('\n==== STATUS BYTE ANALYSIS: $statusByte (0x${statusByte.toRadixString(16).padLeft(2, "0")}) ====');
    log('Binary representation: $bits');
    log('Bit 0 (LSB): ${(statusByte & 0x01) != 0 ? "1" : "0"} - ${describeBit(0, statusByte & 0x01)}');
    log('Bit 1: ${(statusByte & 0x02) != 0 ? "1" : "0"} - ${describeBit(1, statusByte & 0x02)}');
    log('Bit 2: ${(statusByte & 0x04) != 0 ? "1" : "0"} - ${describeBit(2, statusByte & 0x04)}');
    log('Bit 3: ${(statusByte & 0x08) != 0 ? "1" : "0"} - ${describeBit(3, statusByte & 0x08)}');
    log('Bit 4: ${(statusByte & 0x10) != 0 ? "1" : "0"} - ${describeBit(4, statusByte & 0x10)}');
    log('Bit 5: ${(statusByte & 0x20) != 0 ? "1" : "0"} - ${describeBit(5, statusByte & 0x20)}');
    log('Bit 6: ${(statusByte & 0x40) != 0 ? "1" : "0"} - ${describeBit(6, statusByte & 0x40)}');
    log('Bit 7 (MSB): ${(statusByte & 0x80) != 0 ? "1" : "0"} - ${describeBit(7, statusByte & 0x80)}');
    log('========================================');
  }

  /// Helper function to describe the function of each bit according to the common ESC/POS standard
  String describeBit(int bitPosition, int bitValue) {
    bool isSet = bitValue != 0;
    switch (bitPosition) {
      case 0:
        return "Possibly reserved/model specific";
      case 1:
        return isSet ? "Possible additional drawer indicator" : "Normal";
      case 2:
        return isSet ? "Drawer open" : "Drawer closed";
      case 3:
        return isSet ? "Printer OFFLINE" : "Printer ONLINE";
      case 4:
        return isSet
            ? "Model specific indicator (Could be paper sensor)"
            : "Normal";
      case 5:
        return isSet ? "Cover OPEN" : "Cover CLOSED";
      case 6:
        return isSet
            ? "Manual paper feed activated"
            : "Normal paper feed";
      case 7:
        return isSet ? "ERROR present" : "No error";
      default:
        return "Unknown";
    }
  }

  /// Function to create a visual diagram of the bits of a byte
  String createBitDiagram(int statusByte) {
    String bits = statusByte.toRadixString(2).padLeft(8, "0");
    String diagram = '\n+---+---+---+---+---+---+---+---+\n';
    diagram += '| 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 | Bit\n';
    diagram += '+---+---+---+---+---+---+---+---+\n';
    diagram +=
        '| ${bits[0]} | ${bits[1]} | ${bits[2]} | ${bits[3]} | ${bits[4]} | ${bits[5]} | ${bits[6]} | ${bits[7]} |\n';
    diagram += '+---+---+---+---+---+---+---+---+\n';
    diagram +=
        '| ${(statusByte & 0x80) != 0 ? "E" : " "} | ${(statusByte & 0x40) != 0 ? "F" : " "} | ${(statusByte & 0x20) != 0 ? "C" : " "} | ${(statusByte & 0x10) != 0 ? "?" : " "} | ${(statusByte & 0x08) != 0 ? "O" : " "} | ${(statusByte & 0x04) != 0 ? "D" : " "} | ${(statusByte & 0x02) != 0 ? "d" : " "} | ${(statusByte & 0x01) != 0 ? "R" : " "} |\n';
    diagram += '+---+---+---+---+---+---+---+---+\n';
    diagram +=
        ' E=Error, F=Feed, C=Cover, ?=Unknown, O=Offline, D=Drawer, d=drawer2, R=Reserved';
    return diagram;
  }
}