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

  // Constructor que carga la librería nativa
  UsbPlugin() {
    // Determina la ruta de la librería según la plataforma
    final DynamicLibrary library = _loadLibrary();
    // Inicializa los bindings con la librería cargada
    _bindings = UsbPluginsBindings(library);
  }

  // Carga la librería nativa según la plataforma
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
      throw UnsupportedError('Plataforma no soportada');
    }
  }

  // Inicializa la librería USB
  int initLibUsb() {
    return _bindings.libusb_init(nullptr);
  }

  // Finaliza la librería USB
  void exitLibUsb() {
    _bindings.libusb_exit(nullptr);
  }

  // Método para obtener información detallada de los dispositivos
  List<UsbDeviceInfo> getDetailedDeviceList() {
    final deviceListPtr = calloc<Pointer<Pointer<libusb_device>>>();
    final count = _bindings.libusb_get_device_list(nullptr, deviceListPtr);

    List<UsbDeviceInfo> deviceInfoList = [];

    if (count > 0) {
      final deviceList = deviceListPtr.value;

      for (int i = 0; i < count; i++) {
        final device = deviceList[i];

        // Obtener descriptor del dispositivo
        final deviceDescriptor = calloc<libusb_device_descriptor>();
        _bindings.libusb_get_device_descriptor(device, deviceDescriptor);

        // Obtener número de bus y dirección del dispositivo
        final busNumber = _bindings.libusb_get_bus_number(device);
        final deviceAddress = _bindings.libusb_get_device_address(device);

        // Intentar abrir el dispositivo para obtener información de strings
        String? manufacturer;
        String? product;
        String? serialNumber;

        // Crear un puntero para el handle del dispositivo
        final handlePtr = calloc<Pointer<libusb_device_handle>>();

        // Intentar abrir el dispositivo
        final result = _bindings.libusb_open(device, handlePtr);
        if (result != 0) {
          log("Error al abrir el dispositivo: $result");
        } else {
          // Obtener el handle del dispositivo
          final handle = handlePtr.value;
          log("Dispositivo USB abierto con éxito. ProductId: ${deviceDescriptor.ref.idProduct} - VendorId: ${deviceDescriptor.ref.idVendor}");
          // Leer strings si están disponibles
          if (deviceDescriptor.ref.iManufacturer > 0) {
            manufacturer = _getStringDescriptor(
                handle, deviceDescriptor.ref.iManufacturer);
            //log("Fabricante: $manufacturer");
          } else {
            //log("El dispositivo no proporciona un descriptor de fabricante.");
          }

          if (deviceDescriptor.ref.iProduct > 0) {
            product =
                _getStringDescriptor(handle, deviceDescriptor.ref.iProduct);
          }

          if (deviceDescriptor.ref.iSerialNumber > 0) {
            serialNumber = _getStringDescriptor(
                handle, deviceDescriptor.ref.iSerialNumber);
          }

          // Cerrar el dispositivo
          _bindings.libusb_close(handle);
        }

        // Liberar el puntero del handle
        calloc.free(handlePtr);

        // Crear objeto con la información del dispositivo
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

        log('Agregar dispositivo: $deviceInfo');

        deviceInfoList.add(deviceInfo);

        // Liberar el descriptor del dispositivo
        calloc.free(deviceDescriptor);
      }

      // Liberamos la lista de dispositivos
      _bindings.libusb_free_device_list(deviceList, 1);
    }

    // Liberar el puntero de la lista de dispositivos
    calloc.free(deviceListPtr);
    return deviceInfoList;
  }

  // Método auxiliar para obtener string descriptors
  String? _getStringDescriptor(
      Pointer<libusb_device_handle> handle, int index) {
    if (index == 0) {
      return null;
    } // Si el índice es 0, el dispositivo no tiene este string
    final buffer = calloc<Uint8>(256);

    try {
      final length = _bindings.libusb_get_string_descriptor_ascii(
          handle, index, buffer.cast<UnsignedChar>(), 256);

      if (length > 0) {
        return String.fromCharCodes(buffer.asTypedList(length));
      } else {
        log("Error obteniendo descriptor de string con índice $index. Código de error: $length");
        return null;
      }
    } finally {
      calloc.free(buffer);
    }
  }

  // Métodos para abrir y cerrar dispositivos
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

  // Método para transferencia de control
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

// Método para obtener detalles adicionales del dispositivo
  Map<String, dynamic> getDeviceDetails(int vendorId, int productId) {
    final handle = openDevice(vendorId, productId);
    if (handle == null) {
      return {'error': 'No se pudo abrir el dispositivo'};
    }

    try {
      final configDescriptor = calloc<Pointer<libusb_config_descriptor>>();

      // Obtener el descriptor de configuración activo
      final result = _bindings.libusb_get_active_config_descriptor(
          nullptr, configDescriptor);

      if (result < 0) {
        return {
          'error': 'No se pudo obtener el descriptor de configuración',
          'errorCode': result
        };
      }

      final config = configDescriptor.value;

      // Extraer información de interfaces y endpoints
      List<Map<String, dynamic>> interfaces = [];

      // Imprimir los campos disponibles para depuración
      log("Campos disponibles en config.ref: ${config.ref.toString()}");

      // Acceder a las interfaces de manera diferente
      // Necesitamos verificar qué campo contiene las interfaces
      // Posibles nombres: interface, interfaces, itf, etc.

      final numInterfaces = config.ref.bNumInterfaces;
      log("Número de interfaces: $numInterfaces");

      // Usar una aproximación diferente: obtener cada interfaz directamente
      for (int i = 0; i < numInterfaces; i++) {
        // Intenta obtener la interfaz a través de un método alternativo
        // Por ejemplo, podemos usar libusb_get_interface para obtener el número de interfaz actual
        final interfaceNumber = _bindings.libusb_claim_interface(handle, i);

        Map<String, dynamic> interfaceInfo = {
          'interfaceNumber': interfaceNumber,
          'endpoints': <Map<String, dynamic>>[]
        };

        interfaces.add(interfaceInfo);
      }

      // Liberar recursos
      _bindings.libusb_free_config_descriptor(config);

      return {
        'configValue': config.ref.bConfigurationValue,
        'maxPower': config.ref.MaxPower,
        'selfPowered': (config.ref.bmAttributes & 0x40) != 0,
        'remoteWakeup': (config.ref.bmAttributes & 0x20) != 0,
        'numInterfaces': numInterfaces,
        'interfaces': interfaces,
        'note':
            'Información de interfaces limitada debido a la estructura generada'
      };
    } catch (e) {
      return {
        'error': 'Error al obtener detalles del dispositivo',
        'message': e.toString()
      };
    } finally {
      closeDevice(handle);
    }
  }

// Versión corregida que maneja correctamente los punteros potencialmente nulos
// Método modificado que permite tanto enviar como recibir datos
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
    // Abre el dispositivo
    final Pointer<libusb_device_handle>? handleNullable =
        openDevice(vendorId, productId);
    if (handleNullable == nullptr || handleNullable == null) {
      return {'success': false, 'error': 'No se pudo abrir el dispositivo'};
    }

    // Aquí convertimos de Pointer? a Pointer, ahora que sabemos que no es nulo
    final handle = handleNullable;

    try {
      // Verificar si hay un kernel driver activo y desconectarlo si es necesario
      int hasKernelDriver = 0;
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          hasKernelDriver =
              _bindings.libusb_kernel_driver_active(handle, interfaceNumber);
          if (hasKernelDriver == 1) {
            log("Desconectando el driver del kernel...");
            final detachResult =
                _bindings.libusb_detach_kernel_driver(handle, interfaceNumber);
            if (detachResult < 0) {
              log("No se pudo desconectar el driver del kernel: $detachResult");
            } else {
              log("Driver del kernel desconectado con éxito");
            }
          }
        } catch (e) {
          log("Error al verificar/desconectar el driver del kernel: $e");
        }
      }

      // Configurar el dispositivo si es necesario
      final configResult = _bindings.libusb_set_configuration(handle, 1);
      if (configResult < 0) {
        log("Advertencia: No se pudo establecer la configuración: $configResult");
        // Continuamos a pesar del error, ya que algunas impresoras funcionan sin esto
      }

      // Reclamar la interfaz con múltiples intentos
      int claimResult = -1;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts) {
        claimResult = _bindings.libusb_claim_interface(handle, interfaceNumber);
        if (claimResult == 0) break;

        log("Intento ${attempts + 1} fallido con error $claimResult. Reintentando...");
        // Esperar un poco antes de reintentar
        await Future.delayed(Duration(milliseconds: 500));

        attempts++;
      }

      if (claimResult < 0) {
        return {
          'success': false,
          'error':
              'No se pudo reclamar la interfaz después de $maxAttempts intentos',
          'errorCode': claimResult,
          'errorDescription': _getUsbErrorDescription(claimResult)
        };
      }

      // Enviar datos a la impresora
      final buffer = calloc<Uint8>(data.length);
      final bufferList = buffer.asTypedList(data.length);
      bufferList.setAll(0, data);

      final transferredPtr = calloc<Int>();

      log("Enviando ${data.length} bytes al endpoint $endpointAddress...");
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
          'error': 'Error en la transferencia de datos',
          'errorCode': transferResult,
          'errorDescription': _getUsbErrorDescription(transferResult)
        };
      }

      log("Transferencia exitosa: $bytesSent bytes enviados");

      // Si se espera una respuesta, leer los datos de la impresora
      Map<String, dynamic> result = {
        'success': true,
        'bytesSent': bytesSent,
      };

      if (expectResponse) {
        // Crear buffer para la respuesta
        final responseBuffer = calloc<Uint8>(maxResponseLength);
        final responseTransferredPtr = calloc<Int>();

        // Pequeña espera para dar tiempo a la impresora a procesar y preparar la respuesta
        await Future.delayed(Duration(milliseconds: 800));

        log("Leyendo respuesta desde el endpoint $readEndpointAddress...");
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
          log("Respuesta recibida: $bytesReceived bytes");

          if (bytesReceived > 0) {
            // Convertir la respuesta a List<int>
            final responseList = List<int>.filled(bytesReceived, 0);
            for (var i = 0; i < bytesReceived; i++) {
              responseList[i] = responseBuffer[i];
            }

            // Añadir la respuesta al resultado
            result['responseData'] = responseList;
            result['bytesReceived'] = bytesReceived;
          } else {
            result['responseData'] = [];
            result['bytesReceived'] = 0;
          }
        } else {
          log("Error al leer la respuesta: $responseResult");
          result['responseError'] = _getUsbErrorDescription(responseResult);
        }

        calloc.free(responseBuffer);
        calloc.free(responseTransferredPtr);
      }

      // Liberar la interfaz
      _bindings.libusb_release_interface(handle, interfaceNumber);

      // Reconectar el driver del kernel si lo desconectamos
      if (hasKernelDriver == 1 && (Platform.isLinux || Platform.isMacOS)) {
        _bindings.libusb_attach_kernel_driver(handle, interfaceNumber);
      }

      return result;
    } catch (e) {
      return {
        'success': false,
        'error': 'Error al comunicarse con la impresora',
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
      return {'success': false, 'error': 'No se pudo abrir el dispositivo'};
    }

    // Una vez verificado que no es nulo, lo asignamos a una variable no nullable
    final handle = handleNullable;

    try {
      // Obtener el dispositivo a partir del handle
      final device = _bindings.libusb_get_device(handle);

      // Obtener el descriptor del dispositivo
      final deviceDescriptor = calloc<libusb_device_descriptor>();
      final descResult =
          _bindings.libusb_get_device_descriptor(device, deviceDescriptor);
      if (descResult < 0) {
        calloc.free(deviceDescriptor);
        return {
          'success': false,
          'error': 'No se pudo obtener el descriptor del dispositivo',
          'errorCode': descResult
        };
      }

      // Obtener información de configuración
      final configDescPtr = calloc<Pointer<libusb_config_descriptor>>();
      final configResult =
          _bindings.libusb_get_active_config_descriptor(device, configDescPtr);
      if (configResult < 0) {
        calloc.free(deviceDescriptor);
        calloc.free(configDescPtr);
        return {
          'success': false,
          'error': 'No se pudo obtener el descriptor de configuración',
          'errorCode': configResult
        };
      }

      final config = configDescPtr.value;
      final numInterfaces = config.ref.bNumInterfaces;

      // Información básica del dispositivo
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

      // Probar a reclamar interfaces y detectar endpoints manualmente
      for (int i = 0; i < numInterfaces; i++) {
        // Primero desconectamos el driver del kernel si es necesario
        if (Platform.isLinux || Platform.isMacOS) {
          try {
            final hasKernelDriver =
                _bindings.libusb_kernel_driver_active(handle, i);
            if (hasKernelDriver == 1) {
              _bindings.libusb_detach_kernel_driver(handle, i);
            }
          } catch (e) {
            log("Error al verificar/desconectar driver del kernel para interfaz $i: $e");
          }
        }

        // Intentar reclamar la interfaz
        int claimResult = _bindings.libusb_claim_interface(handle, i);
        if (claimResult < 0) {
          log("No se pudo reclamar la interfaz $i: $claimResult");
          continue;
        }

        // Crear una estructura para guardar la información de la interfaz
        Map<String, dynamic> interfaceInfo = {
          'number': i,
          'canClaim': true,
          'endpoints': <Map<String, dynamic>>[]
        };

        // Probar endpoints comunes para impresoras
        List<int> commonEndpoints = [0x01, 0x02, 0x03, 0x81, 0x82, 0x83];

        for (int epAddress in commonEndpoints) {
          // Para simplificar, asumimos que todos los endpoints son de tipo bulk
          bool isOutput = (epAddress & 0x80) ==
              0; // Si el bit más significativo es 0, es de salida

          // Para detectar si un endpoint funciona, podríamos intentar una transferencia de prueba
          // Pero esto podría causar efectos no deseados, así que solo reportamos la dirección
          interfaceInfo['endpoints'].add({
            'address': epAddress,
            'type': 'bulk', // Asumimos tipo bulk para impresoras
            'direction': isOutput ? 'output' : 'input'
          });
        }

        // Liberar la interfaz
        _bindings.libusb_release_interface(handle, i);

        // Reconectar el driver del kernel si es necesario
        if (Platform.isLinux || Platform.isMacOS) {
          try {
            final hasKernelDriver =
                _bindings.libusb_kernel_driver_active(handle, i);
            if (hasKernelDriver == 1) {
              _bindings.libusb_attach_kernel_driver(handle, i);
            }
          } catch (e) {
            log("Error al reconectar driver del kernel para interfaz $i: $e");
          }
        }

        deviceInfo['interfaces'].add(interfaceInfo);
      }

      // Liberar recursos
      _bindings.libusb_free_config_descriptor(config);
      calloc.free(configDescPtr);
      calloc.free(deviceDescriptor);

      return {
        'success': true,
        'deviceInfo': deviceInfo,
        'note':
            'Los endpoints listados son endpoints comunes para impresoras y pueden no corresponder exactamente a los endpoints reales del dispositivo.'
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Error al detectar configuración',
        'exception': e.toString()
      };
    } finally {
      closeDevice(handle);
    }
  }

  // La función findAndClaimValidInterface también necesita ser corregida
  Future<Map<String, dynamic>> findAndClaimValidInterface(
      Pointer<libusb_device_handle>? handleNullable) async {
    if (handleNullable == nullptr || handleNullable == null) {
      return {'success': false, 'error': 'Handle inválido'};
    }

    final handle = handleNullable;

    // Probar con múltiples interfaces
    for (int interfaceNumber = 0; interfaceNumber < 5; interfaceNumber++) {
      // Intentar desconectar el kernel driver para esta interfaz
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          final hasKernelDriver =
              _bindings.libusb_kernel_driver_active(handle, interfaceNumber);
          if (hasKernelDriver == 1) {
            final detachResult =
                _bindings.libusb_detach_kernel_driver(handle, interfaceNumber);
            if (detachResult < 0) continue; // Probar con la siguiente interfaz
          }
        } catch (e) {
          continue; // Probar con la siguiente interfaz
        }
      }

      // Intentar reclamar esta interfaz
      final claimResult =
          _bindings.libusb_claim_interface(handle, interfaceNumber);
      if (claimResult == 0) {
        return {'success': true, 'interfaceNumber': interfaceNumber};
      }
    }

    return {'success': false, 'error': 'No se encontró una interfaz válida'};
  }

  // Método auxiliar para traducir códigos de error de libusb
  String _getUsbErrorDescription(int errorCode) {
    switch (errorCode) {
      case -1:
        return 'LIBUSB_ERROR_IO: Error de I/O';
      case -2:
        return 'LIBUSB_ERROR_INVALID_PARAM: Parámetro inválido';
      case -3:
        return 'LIBUSB_ERROR_ACCESS: Acceso denegado';
      case -4:
        return 'LIBUSB_ERROR_NO_DEVICE: Dispositivo no encontrado';
      case -5:
        return 'LIBUSB_ERROR_NOT_FOUND: Entidad no encontrada';
      case -6:
        return 'LIBUSB_ERROR_BUSY: Recurso ocupado';
      case -7:
        return 'LIBUSB_ERROR_TIMEOUT: Tiempo de espera agotado';
      case -8:
        return 'LIBUSB_ERROR_OVERFLOW: Desbordamiento';
      case -9:
        return 'LIBUSB_ERROR_PIPE: Pipe roto';
      case -10:
        return 'LIBUSB_ERROR_INTERRUPTED: Operación interrumpida';
      case -11:
        return 'LIBUSB_ERROR_NO_MEM: Sin memoria suficiente';
      case -12:
        return 'LIBUSB_ERROR_NOT_SUPPORTED: Operación no soportada';
      case -99:
        return 'LIBUSB_ERROR_OTHER: Error desconocido';
      default:
        return 'Código de error desconocido: $errorCode';
    }
  }

  // Método específico para impresoras ESC/POS
  /*Future<Map<String, dynamic>> printEscPos(
    int vendorId,
    int productId,
    List<int> commandBytes,
    {int timeout = 5000}) async {

  // Convertir List<int> a Uint8List
  final data = Uint8List.fromList(commandBytes);

  // Enviar los comandos a la impresora
  return await sendDataToPrinter(vendorId, productId, data, timeout: timeout);
}*/

  // Modificación del método printEscPos para permitir recibir respuesta si es necesario
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

    // Si se solicita inicialización automática, añadir comando de inicialización al principio
    if (autoInitialize) {
      // ESC @ - Inicializar impresora
      finalCommands.addAll([0x1B, 0x40]);
    }

    // Añadir los comandos principales enviados por parámetro
    finalCommands.addAll(commandBytes);

    // Si se solicita corte automático, añadir comando de corte al final
    if (autoCut) {
      // GS V - Cortar papel (modo total)
      finalCommands.addAll([0x1D, 0x56, 0x00]);
    }

    // Convertir List<int> a Uint8List
    final data = Uint8List.fromList(finalCommands);

    // Intentar enviar con varios endpoints si el predeterminado falla
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

    // Si la operación falló, intentar con un endpoint alternativo
    if (result['success'] == false &&
        result['error']?.contains('transferencia') == true) {
      log("Intentando con endpoint alternativo 0x02...");
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
    // Abre el dispositivo
    final Pointer<libusb_device_handle>? handleNullable =
        openDevice(vendorId, productId);
    if (handleNullable == nullptr || handleNullable == null) {
      return {
        'success': false,
        'error': 'No se pudo abrir el dispositivo',
        'isConnected': false,
        'statusType': command.length >= 3 ? command[2] : 0
      };
    }

    // Aquí convertimos de Pointer? a Pointer, ahora que sabemos que no es nulo
    final handle = handleNullable;

    Map<String, dynamic> statusInfo = {
      'success': false,
      'isConnected': false,
      'rawData': null,
      'statusType': command.length >= 3 ? command[2] : 0
    };
    try {
      // Verificar si hay un kernel driver activo y desconectarlo si es necesario
      int hasKernelDriver = 0;
      if (Platform.isLinux || Platform.isMacOS) {
        try {
          hasKernelDriver =
              _bindings.libusb_kernel_driver_active(handle, interfaceNumber);
          if (hasKernelDriver == 1) {
            log("Desconectando el driver del kernel...");
            final detachResult =
                _bindings.libusb_detach_kernel_driver(handle, interfaceNumber);
            if (detachResult < 0) {
              log("No se pudo desconectar el driver del kernel: $detachResult");
            } else {
              log("Driver del kernel desconectado con éxito");
            }
          }
        } catch (e) {
          log("Error al verificar/desconectar el driver del kernel: $e");
        }
      }

      // Configurar el dispositivo si es necesario
      final configResult = _bindings.libusb_set_configuration(handle, 1);
      if (configResult < 0) {
        log("Advertencia: No se pudo establecer la configuración: $configResult");
        // Continuamos a pesar del error, ya que algunas impresoras funcionan sin esto
      }

      // Reclamar la interfaz con múltiples intentos
      int claimResult = -1;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts) {
        claimResult = _bindings.libusb_claim_interface(handle, interfaceNumber);
        if (claimResult == 0) break;

        log("Intento ${attempts + 1} fallido con error $claimResult. Reintentando...");
        // Esperar un poco antes de reintentar
        await Future.delayed(Duration(milliseconds: 500));

        attempts++;
      }

      if (claimResult < 0) {
        return {
          'success': false,
          'error': 'No se pudo reclamar la interfaz',
          'isConnected': false,
          'statusType': command.length >= 3 ? command[2] : 0
        };
      }

      final buffer = calloc<Uint8>(command.length);
      final bufferList = buffer.asTypedList(command.length);
      bufferList.setAll(0, command);

      final transferredPtr = calloc<Int>();

      log("Enviando comando $command...");
      int transferResult = _bindings.libusb_bulk_transfer(
          handle,
          endpointAddress,
          buffer.cast<UnsignedChar>(),
          command.length,
          transferredPtr,
          timeout);

      await Future.delayed(Duration(milliseconds: 100));

      //final bytesSent = transferredPtr.value;

      calloc.free(buffer);
      calloc.free(transferredPtr);

      if (transferResult < 0) {
        String errorDescription = _getUsbErrorDescription(transferResult);
        return {
          'success': false,
          'error':
              'Error al enviar comando: $command, detalle: $errorDescription',
          'isConnected': false,
          'statusType': command.length >= 3 ? command[2] : 0
        };
      }

      //log("Transferencia exitosa: $bytesSent bytes enviados");

      Uint8List buffer2 = Uint8List(512);
      final Pointer<UnsignedChar> dataPointer =
          malloc.allocate<UnsignedChar>(buffer2.length);
      for (var i = 0; i < buffer2.length; i++) {
        dataPointer[i] = buffer[i];
      }

      final Pointer<Int> transferredPointer = malloc.allocate<Int>(1);
      transferredPointer.value = 0;

      // Llamar a la función correctamente
      int readResult = _bindings.libusb_bulk_transfer(
        handle, // libusb_device_handle*
        0x81, // unsigned char endpoint
        dataPointer, // unsigned char* data
        buffer2.length, // int length
        transferredPointer, // int* transferred
        timeout, // unsigned int timeout
      );

      // Leer cuántos bytes se transfirieron
      int bytesReceived = transferredPointer.value;

      if (readResult == 0 && bytesReceived > 0) {
        // Copiar los datos recibidos de vuelta a un Uint8List
        Uint8List receivedData = Uint8List(bytesReceived);
        for (var i = 0; i < bytesReceived; i++) {
          receivedData[i] = dataPointer[i];
        }

        // Determinar qué tipo de comando es según el tercer byte
        int statusType = command.length >= 3 ? command[2] : 0;

        statusInfo['success'] = true;
        statusInfo['isConnected'] = true;
        statusInfo['rawData'] = receivedData;
        statusInfo['binaryResponse'] =
            receivedData[0].toRadixString(2).padLeft(8, '0');
        statusInfo['statusType'] = statusType;

        // Interpretar los datos según el tipo de estado
        if (bytesReceived > 0) {
          //interpretPrinterStatus(receivedData[0]);
          //bool isOnline = (receivedData[0] & (1 << 3)) == 0;
          //log('Impresora en línea: $isOnline');
          //statusInfo['status'] = 'Impresora en línea: $isOnline';

          // Interpretar la respuesta según el tipo de comando
          switch (statusType) {
            case 1: // Estado de la impresora [0x10, 0x04, 0x01]
              statusInfo['isOnline'] = (receivedData[0] & (1 << 3)) == 0;
              statusInfo['cashDrawerOpen'] = (receivedData[0] & (1 << 2)) != 0;
              break;

            case 2: // Estado offline [0x10, 0x04, 0x02]
              statusInfo['isCoverOpen'] = (receivedData[0] & (1 << 2)) != 0;
              statusInfo['isPaperFeedByButton'] =
                  (receivedData[0] & (1 << 3)) != 0;
              break;

            case 4: // Estado del sensor de papel [0x10, 0x04, 0x04]
              // Evaluamos los bits 2-3 (estado del papel cerca del final)
              bool bit2 = (receivedData[0] & (1 << 2)) != 0;
              bool bit3 = (receivedData[0] & (1 << 3)) != 0;

              // Evaluamos los bits 5-6 (estado del sensor de fin de papel)
              bool bit5 = (receivedData[0] & (1 << 5)) != 0;
              bool bit6 = (receivedData[0] & (1 << 6)) != 0;

              statusInfo['paperStatus'] = {
                'paperNearEnd': bit2 ||
                    bit3, // Si cualquiera de estos bits está activado, el papel está cerca del final
                'paperEnd': bit5 ||
                    bit6, // Si cualquiera de estos bits está activado, se ha detectado el fin del papel
                'paperPresent': !(bit5 ||
                    bit6), // Si los bits 5-6 están desactivados, hay papel presente
                'paperAdequate': !(bit2 ||
                    bit3), // Si los bits 2-3 están desactivados, el papel es adecuado
              };
              break;

            default:
              statusInfo['error'] = 'Tipo de comando no reconocido';
          }
        }
      } else {
        log("Error: ${_bindings.libusb_error_name(readResult)}");
        log("Description: ${_getUsbErrorDescription(readResult)}");
        statusInfo['error'] =
            'Error al leer respuesta: ${_bindings.libusb_error_name(readResult)}';
      }

      // Liberar la memoria
      malloc.free(dataPointer);
      malloc.free(transferredPointer);

      // Liberar la interfaz
      _bindings.libusb_release_interface(handle, interfaceNumber);

      // Reconectar el driver del kernel si lo desconectamos
      if (hasKernelDriver == 1 && (Platform.isLinux || Platform.isMacOS)) {
        _bindings.libusb_attach_kernel_driver(handle, interfaceNumber);
      }
    } catch (e) {
      log('Exception: $e');
      return {
        'success': false,
        'error': 'Error al comunicarse con la impresora: ${e.toString()}',
        'isConnected': false,
        'statusType': command.length >= 3 ? command[2] : 0
      };
    } finally {
      closeDevice(handle);
    }
    return statusInfo;
  }

  /// Función sencilla para interpretar el byte de estado de la impresora 3nStart RPT008
  void interpretPrinterStatus(int statusByte) {
    // Convertir a representación binaria para facilitar el análisis
    String bits = statusByte.toRadixString(2).padLeft(8, '0');

    log('\n==== ESTADO DE LA IMPRESORA 3NSTART RPT008 ====');
    log('Byte recibido: 0x${statusByte.toRadixString(16).padLeft(2, "0")} ($statusByte)');
    log('Representación binaria: $bits');

    // Analizar cada bit individualmente
    bool error = (statusByte & 0x80) != 0; // Bit 7
    bool paperFeed = (statusByte & 0x40) != 0; // Bit 6
    bool coverOpen = (statusByte & 0x20) != 0; // Bit 5
    bool sensorBit = (statusByte & 0x10) != 0; // Bit 4 (específico del modelo)
    bool offline = (statusByte & 0x08) != 0; // Bit 3
    bool drawer1 = (statusByte & 0x04) != 0; // Bit 2
    bool drawer2 = (statusByte & 0x02) != 0; // Bit 1
    //bool reserved = (statusByte & 0x01) != 0; // Bit 0

    // Imprimir interpretación
    log('\nInterpretación:');
    log('- Estado Online/Offline: ${offline ? "OFFLINE" : "ONLINE"}');
    log('- Tapa: ${coverOpen ? "ABIERTA" : "CERRADA"}');
    log('- Error: ${error ? "SÍ" : "NO"}');
    log('- Gaveta: ${(drawer1 || drawer2) ? "ABIERTA" : "CERRADA"}');
    log('- Alimentación manual: ${paperFeed ? "ACTIVA" : "INACTIVA"}');
    log('- Sensor especial (bit 4): ${sensorBit ? "ACTIVO" : "INACTIVO"}');

    // Para el caso específico de 0x16 (22)
    if (statusByte == 22) {
      log('\nResumen para 0x16 (22):');
      log('La impresora está ONLINE, con la tapa CERRADA y sin errores.');
      log('La gaveta parece estar ABIERTA (bits 1 y 2 activados).');
      log('El bit 4 está activo, que podría indicar un estado específico');
      log('del sensor de papel u otra función específica del modelo.');
    }

    log('\nDiagrama de bits:');
    log('+---+---+---+---+---+---+---+---+');
    log('| 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 | Posición');
    log('+---+---+---+---+---+---+---+---+');
    log('| ${bits[0]} | ${bits[1]} | ${bits[2]} | ${bits[3]} | ${bits[4]} | ${bits[5]} | ${bits[6]} | ${bits[7]} | Valor');
    log('+---+---+---+---+---+---+---+---+');
    log('| E | F | C | S | O | D1| D2| R | Significado');
    log('+---+---+---+---+---+---+---+---+');
    log(' E=Error, F=Feed, C=Cover, S=Sensor, O=Offline, D=Drawer, R=Reserved');

    log('\n========================================');
  }

  /// Función de utilidad para mostrar el estado completo
  void printFullStatus(Map<String, dynamic> statusMap) {
    if (!statusMap['success']) {
      log('Error obteniendo el estado: ${statusMap['error']}');
      return;
    }

    log('\n==== ESTADO DE LA IMPRESORA 3NSTART RPT008 ====');

    if (statusMap.containsKey('printerStatus')) {
      final status = statusMap['printerStatus']['status'];
      log('\n-- ESTADO GENERAL --');
      log('Gaveta: ${status['drawer']}');
      log('Online: ${status['online'] ? 'Sí' : 'No'}');
      log('Tapa abierta: ${status['coverOpen'] ? 'Sí' : 'No'}');
      log('Alimentación de papel manual: ${status['paperFeed'] ? 'Activa' : 'Inactiva'}');
      log('Error: ${status['error'] ? 'Sí' : 'No'}');
      log('Byte recibido: ${status['rawByte']}');
    }

    if (statusMap.containsKey('offlineStatus')) {
      final status = statusMap['offlineStatus']['status'];
      log('\n-- ESTADO OFFLINE --');
      log('Tapa abierta: ${status['coverOpen'] ? 'Sí' : 'No'}');
      log('Botón Feed presionado: ${status['paperFeedStop'] ? 'Sí' : 'No'}');
      log('Error ocurrido: ${status['errorOccurred'] ? 'Sí' : 'No'}');
      log('Offline: ${status['offline'] ? 'Sí' : 'No'}');
      log('Error auto-recuperable: ${status['autoRecoverableError'] ? 'Sí' : 'No'}');
      log('Esperando volver online: ${status['waitingForOnline'] ? 'Sí' : 'No'}');
      log('Byte recibido: ${status['rawByte']}');
    }

    if (statusMap.containsKey('errorStatus')) {
      final status = statusMap['errorStatus']['status'];
      log('\n-- ESTADO DE ERROR --');
      log('Error mecánico: ${status['mechanicalError'] ? 'Sí' : 'No'}');
      log('Error auto-recuperable: ${status['autoRecoverError'] ? 'Sí' : 'No'}');
      log('Error no recuperable: ${status['notRecoverableError'] ? 'Sí' : 'No'}');
      log('Error en cortador: ${status['autoRecoverableCutterError'] ? 'Sí' : 'No'}');
      log('Tapa abierta: ${status['coverOpen'] ? 'Sí' : 'No'}');
      log('Sin papel: ${status['paperEmpty'] ? 'Sí' : 'No'}');
      log('Byte recibido: ${status['rawByte']}');
    }

    if (statusMap.containsKey('paperStatus')) {
      final status = statusMap['paperStatus']['status'];
      log('\n-- ESTADO DEL PAPEL --');
      log('Papel por acabarse: ${status['paperNearEnd'] ? 'Sí' : 'No'}');
      log('Sin papel: ${status['paperEmpty'] ? 'Sí' : 'No'}');
      log('Detenido por papel por acabarse: ${status['paperNearEndStop'] ? 'Sí' : 'No'}');
      log('Detenido por falta de papel: ${status['paperEmptyStop'] ? 'Sí' : 'No'}');
      log('Byte recibido: ${status['rawByte']}');
    }

    log('\n========================================');
  }

  /// Función de depuración para analizar el byte
  void analyzeStatusByte(int statusByte) {
    String bits = statusByte.toRadixString(2).padLeft(8, "0");
    log('\n==== ANÁLISIS DE BYTE DE ESTADO: $statusByte (0x${statusByte.toRadixString(16).padLeft(2, "0")}) ====');
    log('Representación binaria: $bits');
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

  /// Función auxiliar para describir la función de cada bit según el estándar ESC/POS común
  String describeBit(int bitPosition, int bitValue) {
    bool isSet = bitValue != 0;
    switch (bitPosition) {
      case 0:
        return "Posiblemente reservado/específico del modelo";
      case 1:
        return isSet ? "Posible indicador adicional de gaveta" : "Normal";
      case 2:
        return isSet ? "Gaveta abierta" : "Gaveta cerrada";
      case 3:
        return isSet ? "Impresora OFFLINE" : "Impresora ONLINE";
      case 4:
        return isSet
            ? "Indicador específico del modelo (Podría ser sensor de papel)"
            : "Normal";
      case 5:
        return isSet ? "Tapa ABIERTA" : "Tapa CERRADA";
      case 6:
        return isSet
            ? "Alimentación de papel manual activada"
            : "Alimentación de papel normal";
      case 7:
        return isSet ? "ERROR presente" : "Sin error";
      default:
        return "Desconocido";
    }
  }

  /// Función para crear un diagrama visual de los bits de un byte
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
