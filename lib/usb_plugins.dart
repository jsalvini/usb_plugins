// ignore_for_file: constant_identifier_names

import 'dart:developer';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:usb_plugins/usb_device_info.dart';
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
            //print("Fabricante: $manufacturer");
          } else {
            //print("El dispositivo no proporciona un descriptor de fabricante.");
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

  // Función para consultar el estado de la impresora
  // Función para consultar el estado de la impresora 3nstar RPT-008
  Future<Map<String, dynamic>> checkPrinterStatus(
    int vendorId,
    int productId,
  ) async {
    Map<String, dynamic> result = {
      'isOnline': false,
      'paperOut': false,
      'coverOpen': false,
      'paperNearEnd': false,
      'rawData': [], // Almacenará los bytes crudos de respuesta
      'debugInfo': '' // Almacenará información de depuración
    };

    String debugInfo = '';

    try {
      // Para 3nstar RPT-008, usamos DLE EOT n para consultar el estado
      // n = 1: Transmite estado de la impresora
      List<int> statusCommand = [0x10, 0x04, 0x01]; // DLE EOT 1
      debugInfo +=
          "Enviando comando de estado (DLE EOT 1): ${statusCommand.map((e) => '0x${e.toRadixString(16)}').join(', ')}\n";

      var printerStatus = await printEscPos(
        vendorId,
        productId,
        statusCommand,
        timeout: 3000,
        expectResponse: true,
      );

      debugInfo += "Respuesta recibida: $printerStatus\n";

      if (printerStatus['success'] == true) {
        List<int>? response = printerStatus['data'] as List<int>?;

        if (response != null && response.isNotEmpty) {
          result['rawData'] = response;
          debugInfo +=
              "Bytes recibidos: ${response.map((e) => '0x${e.toRadixString(16)}').join(', ')}\n";

          int status = response[0];
          debugInfo +=
              "Primer byte de estado: 0x${status.toRadixString(16)} (binario: ${status.toRadixString(2).padLeft(8, '0')})\n";

          // Evaluación de cada bit relevante para depuración
          bool bit3 = ((status >> 3) & 1) == 0;
          bool bit4 = ((status >> 4) & 1) == 1;
          bool bit5 = ((status >> 5) & 1) == 1;

          debugInfo += "Bit 3 (En línea): ${bit3 ? 'Activo' : 'Inactivo'}\n";
          debugInfo +=
              "Bit 4 (Tapa abierta): ${bit4 ? 'Activo' : 'Inactivo'}\n";
          debugInfo += "Bit 5 (Sin papel): ${bit5 ? 'Activo' : 'Inactivo'}\n";

          // Establecer estados
          result['isOnline'] = bit3;
          result['coverOpen'] = bit4;
          result['paperOut'] = bit5;
        } else {
          debugInfo +=
              "No se recibieron datos de respuesta o respuesta vacía\n";
        }
      } else {
        debugInfo +=
            "Error al enviar comando de estado: ${printerStatus['error'] ?? 'Desconocido'}\n";
      }

      // Consultar estado del papel - DLE EOT 4
      List<int> paperStatusCommand = [0x10, 0x04, 0x04]; // DLE EOT 4
      debugInfo +=
          "Enviando comando de estado de papel (DLE EOT 4): ${paperStatusCommand.map((e) => '0x${e.toRadixString(16)}').join(', ')}\n";

      var paperStatus = await printEscPos(
        vendorId,
        productId,
        paperStatusCommand,
        timeout: 3000,
        // No uses autoInitialize ni autoCut para comandos de estado
      );

      debugInfo += "Respuesta recibida para estado del papel: $paperStatus\n";

      if (paperStatus['success'] == true) {
        List<int>? response = paperStatus['data'] as List<int>?;

        if (response != null && response.isNotEmpty) {
          result['rawPaperData'] = response;
          debugInfo +=
              "Bytes recibidos para papel: ${response.map((e) => '0x${e.toRadixString(16)}').join(', ')}\n";

          int status = response[0];
          debugInfo +=
              "Primer byte de estado de papel: 0x${status.toRadixString(16)} (binario: ${status.toRadixString(2).padLeft(8, '0')})\n";

          // Evaluación de cada bit relevante para depuración
          bool bit6 = ((status >> 6) & 1) == 1;
          debugInfo +=
              "Bit 6 (Papel por acabarse): ${bit6 ? 'Activo' : 'Inactivo'}\n";

          // Establecer estado
          result['paperNearEnd'] = bit6;
        } else {
          debugInfo +=
              "No se recibieron datos de respuesta para estado del papel o respuesta vacía\n";
        }
      } else {
        debugInfo +=
            "Error al enviar comando de estado de papel: ${paperStatus['error'] ?? 'Desconocido'}\n";
      }

      // Probar comandos alternativos para esta impresora específica
      // Algunas impresoras 3nstar usan GS r n en lugar de DLE EOT
      debugInfo += "\nPROBANDO COMANDOS ALTERNATIVOS:\n";

      List<int> altStatusCommand = [0x1D, 0x72, 0x01]; // GS r 1
      debugInfo +=
          "Enviando comando alternativo (GS r 1): ${altStatusCommand.map((e) => '0x${e.toRadixString(16)}').join(', ')}\n";

      var altStatus = await printEscPos(vendorId, productId, altStatusCommand,
          timeout: 3000);

      debugInfo += "Respuesta recibida para comando alternativo: $altStatus\n";

      if (altStatus['success'] == true) {
        List<int>? response = altStatus['data'] as List<int>?;
        if (response != null && response.isNotEmpty) {
          debugInfo +=
              "Bytes recibidos para comando alternativo: ${response.map((e) => '0x${e.toRadixString(16)}').join(', ')}\n";
        }
      }

      // Guardar información de depuración en el resultado
      result['debugInfo'] = debugInfo;

      return result;
    } catch (e) {
      debugInfo += "EXCEPCIÓN: $e\n";
      return {
        'error': e.toString(),
        'isOnline': false,
        'paperOut': true,
        'coverOpen': false,
        'paperNearEnd': false,
        'debugInfo': debugInfo
      };
    }
  }

  // Función para interpretar los datos de estado recibidos
  Map<String, dynamic> interpretPrinterStatus(List<int> statusData) {
    Map<String, dynamic> status = {};

    if (statusData.isEmpty) {
      return {'error': 'No se recibieron datos de estado'};
    }

    // Primer byte del estado de la impresora (según las imágenes del manual)
    int printerStatus = statusData[0];

    // Según la imagen del manual para n = 1 (Printer Status)
    status['cashDrawerOpen'] = (printerStatus & 0x04) != 0; // Bit 2
    status['offline'] = (printerStatus & 0x08) != 0; // Bit 3 (Off-line)

    // Información adicional si hay más bytes en la respuesta
    if (statusData.length > 1) {
      // Si la impresora envía más información, como en el manual
      //int additionalStatus = statusData[1];

      // Puedes agregar más interpretaciones según el manual
      // Por ejemplo, para n = 2 (Off-line Status)
      if (statusData.length > 1) {
        int offlineStatus = statusData[1];
        status['coverOpen'] = (offlineStatus & 0x04) != 0; // Bit 2
        status['paperFeedButton'] = (offlineStatus & 0x08) != 0; // Bit 3
      }
    }

    // Información de depuración
    status['rawData'] = statusData
        .map((e) => '0x${e.toRadixString(16).padLeft(2, '0')}')
        .join(', ');

    return status;
  }

  void initializeAndGetStatus(
    int vendorId,
    int productId, {
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
      //return {'success': false, 'error': 'No se pudo abrir el dispositivo'};
      return;
    }

    // Aquí convertimos de Pointer? a Pointer, ahora que sabemos que no es nulo
    final handle = handleNullable;

    Map<String, dynamic> statusInfo = {
      'success': false,
      'rawData': null,
      'status': {}
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
        return;
      }

      List<int> command = [0x10, 0x04, 0x01];

      final buffer = calloc<Uint8>(command.length);
      final bufferList = buffer.asTypedList(command.length);
      bufferList.setAll(0, command);

      final transferredPtr = calloc<Int>();

      log("Enviando comando ${command.length} bytes al endpoint $endpointAddress...");
      int transferResult = _bindings.libusb_bulk_transfer(
          handle,
          endpointAddress,
          buffer.cast<UnsignedChar>(),
          command.length,
          transferredPtr,
          timeout);

      await Future.delayed(Duration(milliseconds: 5000));

      final bytesSent = transferredPtr.value;

      calloc.free(buffer);
      calloc.free(transferredPtr);

      if (transferResult < 0) {
        statusInfo['error'] = 'Error al leer respuesta: $transferResult';
      }

      log("Transferencia exitosa: $bytesSent bytes enviados");

      Uint8List buffer2 = Uint8List(512);
      // Usar UnsignedChar en lugar de Uint8
      final Pointer<UnsignedChar> dataPointer =
          malloc.allocate<UnsignedChar>(buffer2.length);
      // Copiar los datos del Uint8List al puntero
      for (var i = 0; i < buffer2.length; i++) {
        dataPointer[i] = buffer[i];
      }

      // Crear un puntero para recibir la cantidad de bytes transferidos
      final Pointer<Int> transferredPointer = malloc.allocate<Int>(1);
      // Inicializar a cero
      transferredPointer.value = 0;

      // Llamar a la función correctamente
      int result = _bindings.libusb_bulk_transfer(
        handle, // libusb_device_handle*
        0x81, // unsigned char endpoint
        dataPointer, // unsigned char* data
        buffer2.length, // int length
        transferredPointer, // int* transferred
        timeout, // unsigned int timeout
      );

      // Leer cuántos bytes se transfirieron
      int bytesRead = transferredPointer.value;

      // Copiar los datos recibidos de vuelta a un Uint8List
      Uint8List receivedData = Uint8List(bytesRead);
      for (var i = 0; i < bytesRead; i++) {
        receivedData[i] = dataPointer[i];
      }

      statusInfo['success'] = true;
      statusInfo['rawData'] = receivedData;

      // Liberar la memoria
      malloc.free(dataPointer);
      malloc.free(transferredPointer);

      if (result == 0) {
        print("Éxito! Bytes leídos: $bytesRead");
        print("Datos: $receivedData");
        statusInfo['status'] = interpretStatusByte(0x01, receivedData[0]);
      } else {
        print("Error: ${_bindings.libusb_error_name(result)}");
      }

      printFullStatus(statusInfo);

      // Liberar la interfaz
      _bindings.libusb_release_interface(handle, interfaceNumber);

      // Reconectar el driver del kernel si lo desconectamos
      if (hasKernelDriver == 1 && (Platform.isLinux || Platform.isMacOS)) {
        _bindings.libusb_attach_kernel_driver(handle, interfaceNumber);
      }
    } catch (e) {
      print('Exception: $e');
    } finally {
      closeDevice(handle);
    }
  }

  /// Interpreta el byte de estado según su tipo, ajustado para la impresora 3nStart RPT008
  Map<String, dynamic> interpretStatusByte(int statusType, int statusByte) {
    Map<String, dynamic> interpretation = {};

    // Convertir el byte a un string de bits para facilitar la interpretación
    String bits = statusByte.toRadixString(2).padLeft(8, "0");
    print(
        'Byte recibido: 0x${statusByte.toRadixString(16).padLeft(2, "0")} ($statusByte) - Bits: $bits');

    switch (statusType) {
      case 0x01: // Estado de la impresora
        // Para el valor 22 (0x16) = 00010110 en binario
        // Bit 0 (LSB): No usado típicamente, valor 0
        // Bit 1: 1 - Puede indicar gaveta abierta en algunas impresoras
        // Bit 2: 1 - Gaveta abierta (en especificación estándar)
        // Bit 3: 0 - Online (0 = online, 1 = offline en especificación estándar)
        // Bit 4: 1 - Podría ser un indicador específico del modelo
        // Bit 5: 0 - Tapa cerrada (0 = cerrada, 1 = abierta en especificación estándar)
        // Bit 6: 0 - No hay alimentación de papel manual
        // Bit 7 (MSB): 0 - No hay error (0 = no error, 1 = error en especificación estándar)

        interpretation['drawer'] =
            ((statusByte & 0x04) != 0 || (statusByte & 0x02) != 0)
                ? 'abierto'
                : 'cerrado';
        interpretation['online'] = (statusByte & 0x08) == 0 ? true : false;
        interpretation['coverOpen'] = (statusByte & 0x20) != 0 ? true : false;
        interpretation['paperFeed'] = (statusByte & 0x40) != 0 ? true : false;
        interpretation['error'] = (statusByte & 0x80) != 0 ? true : false;
        interpretation['unknown_bit4'] =
            (statusByte & 0x10) != 0 ? true : false; // Bit 4 específico
        break;

      case 0x02: // Estado offline
        interpretation['coverOpen'] = (statusByte & 0x01) != 0 ? true : false;
        interpretation['paperFeedStop'] =
            (statusByte & 0x02) != 0 ? true : false;
        interpretation['errorOccurred'] =
            (statusByte & 0x04) != 0 ? true : false;
        interpretation['offline'] = (statusByte & 0x08) != 0 ? true : false;
        interpretation['autoRecoverableError'] =
            (statusByte & 0x20) != 0 ? true : false;
        interpretation['waitingForOnline'] =
            (statusByte & 0x40) != 0 ? true : false;
        break;

      case 0x03: // Estado de error
        interpretation['mechanicalError'] =
            (statusByte & 0x01) != 0 ? true : false;
        interpretation['autoRecoverError'] =
            (statusByte & 0x02) != 0 ? true : false;
        interpretation['notRecoverableError'] =
            (statusByte & 0x04) != 0 ? true : false;
        interpretation['autoRecoverableCutterError'] =
            (statusByte & 0x08) != 0 ? true : false;
        interpretation['coverOpen'] = (statusByte & 0x20) != 0 ? true : false;
        interpretation['paperEmpty'] = (statusByte & 0x40) != 0 ? true : false;
        break;

      case 0x04: // Estado del papel
        interpretation['paperNearEnd'] =
            (statusByte & 0x01) != 0 ? true : false;
        interpretation['paperEmpty'] = (statusByte & 0x02) != 0 ? true : false;
        interpretation['paperNearEndStop'] =
            (statusByte & 0x08) != 0 ? true : false;
        interpretation['paperEmptyStop'] =
            (statusByte & 0x10) != 0 ? true : false;
        break;

      default:
        interpretation['unknown'] = 'Tipo de estado no reconocido';
    }

    interpretation['rawByte'] =
        '0x${statusByte.toRadixString(16).padLeft(2, "0")}';
    interpretation['binaryBits'] = bits;

    return interpretation;
  }

  /// Función de utilidad para mostrar el estado completo
  void printFullStatus(Map<String, dynamic> statusMap) {
    if (!statusMap['success']) {
      print('Error obteniendo el estado: ${statusMap['error']}');
      return;
    }

    print('\n==== ESTADO DE LA IMPRESORA 3NSTART RPT008 ====');

    if (statusMap.containsKey('printerStatus')) {
      final status = statusMap['printerStatus']['status'];
      print('\n-- ESTADO GENERAL --');
      print('Gaveta: ${status['drawer']}');
      print('Online: ${status['online'] ? 'Sí' : 'No'}');
      print('Tapa abierta: ${status['coverOpen'] ? 'Sí' : 'No'}');
      print(
          'Alimentación de papel manual: ${status['paperFeed'] ? 'Activa' : 'Inactiva'}');
      print('Error: ${status['error'] ? 'Sí' : 'No'}');
      print('Byte recibido: ${status['rawByte']}');
    }

    if (statusMap.containsKey('offlineStatus')) {
      final status = statusMap['offlineStatus']['status'];
      print('\n-- ESTADO OFFLINE --');
      print('Tapa abierta: ${status['coverOpen'] ? 'Sí' : 'No'}');
      print('Botón Feed presionado: ${status['paperFeedStop'] ? 'Sí' : 'No'}');
      print('Error ocurrido: ${status['errorOccurred'] ? 'Sí' : 'No'}');
      print('Offline: ${status['offline'] ? 'Sí' : 'No'}');
      print(
          'Error auto-recuperable: ${status['autoRecoverableError'] ? 'Sí' : 'No'}');
      print(
          'Esperando volver online: ${status['waitingForOnline'] ? 'Sí' : 'No'}');
      print('Byte recibido: ${status['rawByte']}');
    }

    if (statusMap.containsKey('errorStatus')) {
      final status = statusMap['errorStatus']['status'];
      print('\n-- ESTADO DE ERROR --');
      print('Error mecánico: ${status['mechanicalError'] ? 'Sí' : 'No'}');
      print(
          'Error auto-recuperable: ${status['autoRecoverError'] ? 'Sí' : 'No'}');
      print(
          'Error no recuperable: ${status['notRecoverableError'] ? 'Sí' : 'No'}');
      print(
          'Error en cortador: ${status['autoRecoverableCutterError'] ? 'Sí' : 'No'}');
      print('Tapa abierta: ${status['coverOpen'] ? 'Sí' : 'No'}');
      print('Sin papel: ${status['paperEmpty'] ? 'Sí' : 'No'}');
      print('Byte recibido: ${status['rawByte']}');
    }

    if (statusMap.containsKey('paperStatus')) {
      final status = statusMap['paperStatus']['status'];
      print('\n-- ESTADO DEL PAPEL --');
      print('Papel por acabarse: ${status['paperNearEnd'] ? 'Sí' : 'No'}');
      print('Sin papel: ${status['paperEmpty'] ? 'Sí' : 'No'}');
      print(
          'Detenido por papel por acabarse: ${status['paperNearEndStop'] ? 'Sí' : 'No'}');
      print(
          'Detenido por falta de papel: ${status['paperEmptyStop'] ? 'Sí' : 'No'}');
      print('Byte recibido: ${status['rawByte']}');
    }

    print('\n========================================');
  }

  /// Función de depuración para analizar el byte
  void analyzeStatusByte(int statusByte) {
    String bits = statusByte.toRadixString(2).padLeft(8, "0");
    print(
        '\n==== ANÁLISIS DE BYTE DE ESTADO: ${statusByte} (0x${statusByte.toRadixString(16).padLeft(2, "0")}) ====');
    print('Representación binaria: $bits');
    print(
        'Bit 0 (LSB): ${(statusByte & 0x01) != 0 ? "1" : "0"} - ${describeBit(0, statusByte & 0x01)}');
    print(
        'Bit 1: ${(statusByte & 0x02) != 0 ? "1" : "0"} - ${describeBit(1, statusByte & 0x02)}');
    print(
        'Bit 2: ${(statusByte & 0x04) != 0 ? "1" : "0"} - ${describeBit(2, statusByte & 0x04)}');
    print(
        'Bit 3: ${(statusByte & 0x08) != 0 ? "1" : "0"} - ${describeBit(3, statusByte & 0x08)}');
    print(
        'Bit 4: ${(statusByte & 0x10) != 0 ? "1" : "0"} - ${describeBit(4, statusByte & 0x10)}');
    print(
        'Bit 5: ${(statusByte & 0x20) != 0 ? "1" : "0"} - ${describeBit(5, statusByte & 0x20)}');
    print(
        'Bit 6: ${(statusByte & 0x40) != 0 ? "1" : "0"} - ${describeBit(6, statusByte & 0x40)}');
    print(
        'Bit 7 (MSB): ${(statusByte & 0x80) != 0 ? "1" : "0"} - ${describeBit(7, statusByte & 0x80)}');
    print('========================================');
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
