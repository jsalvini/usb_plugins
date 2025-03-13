import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:usb_plugins/usb_plugins.dart';

class PrinterTestScreen extends StatefulWidget {
  const PrinterTestScreen({super.key});

  @override
  State<PrinterTestScreen> createState() => _PrinterTestScreenState();
}

class _PrinterTestScreenState extends State<PrinterTestScreen> {
  final UsbPlugin usbPlugin = UsbPlugin();
  bool isInitialized = false;
  String statusMessage = "No inicializado";
  String debugText = '';

  // IDs de la impresora
  final int vendorId = 0x067b;
  final int productId = 0x2305;

  // Resultados del estado de la impresora
  bool isOnline = false;
  bool paperOut = false;
  bool coverOpen = false;
  bool paperNearEnd = false;

  @override
  void initState() {
    super.initState();
    _initializeUsbPlugin();
  }

  @override
  void dispose() {
    if (isInitialized) {
      usbPlugin.exitLibUsb();
    }
    super.dispose();
  }

  Future<void> _initializeUsbPlugin() async {
    final initResult = usbPlugin.initLibUsb();
    if (initResult != 0) {
      setState(() {
        statusMessage = 'Error al inicializar libusb: $initResult';
        isInitialized = false;
      });
      return;
    }

    setState(() {
      statusMessage = 'Librería USB inicializada correctamente';
      isInitialized = true;
    });
  }

  Future<void> _printTestTicket() async {
    if (!isInitialized) {
      setState(() {
        statusMessage = 'USB no inicializado. Inicializa primero.';
      });
      return;
    }

    try {
      setState(() {
        statusMessage = 'Enviando datos a la impresora...';
      });

      // Comandos ESC/POS para el ticket de prueba
      final List<int> commands = [
        0x1B, 0x40, // Inicializar impresora

        // Encabezado - Centrado
        0x1B, 0x61, 0x01, // Centrar
        ...utf8.encode('Mi Comercio\n'),
        ...utf8.encode('Av. Principal 123\n'),
        ...utf8.encode('Tel: 555-1234\n'),
        0x1B, 0x64, 0x01, // Espaciado

        // Línea separadora
        ...utf8.encode('------------------------------\n'),

        // Detalle del ticket (Izquierda)
        0x1B, 0x61, 0x00, // Alinear a la izquierda
        ...utf8.encode('Cant  Descripción    Precio\n'),
        ...utf8.encode('--------------------------------\n'),
        ...utf8.encode(' 1   Producto A      \$10.00\n'),
        ...utf8.encode(' 2   Producto B      \$20.00\n'),
        ...utf8.encode(' 1   Producto C      \$15.00\n'),

        // Subtotal y total
        ...utf8.encode('------------------------------\n'),
        0x1B, 0x61, 0x02, // Alinear a la derecha
        ...utf8.encode('Subtotal:       \$45.00\n'),
        ...utf8.encode('IVA (21%):      \$9.45\n'),
        ...utf8.encode('Total:          \$54.45\n'),

        // Espaciado y mensaje final
        0x1B, 0x64, 0x02, // Avanzar 2 líneas
        0x1B, 0x61, 0x01, // Centrar
        ...utf8.encode('¡Gracias por su compra!\n'),

        0x1B, 0x64, 0x03, // Avanzar 3 líneas
        0x1D, 0x56, 0x00, // Corte de papel
      ];

      // Enviar comandos a la impresora
      final result = await usbPlugin.printEscPos(vendorId, productId, commands);

      if (result['success'] == true) {
        setState(() {
          statusMessage =
              'Datos enviados correctamente: ${result['bytesSent']} bytes';
        });
      } else {
        setState(() {
          statusMessage = 'Error al enviar datos: ${result['error']}';
          if (result.containsKey('errorCode')) {
            statusMessage += '\nCódigo de error: ${result['errorCode']}';
          }
        });
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Excepción: $e';
      });
    }
  }

  Future<void> _checkPrinterStatus() async {
    if (!isInitialized) {
      setState(() {
        statusMessage = 'USB no inicializado. Inicializa primero.';
      });
      return;
    }

    try {
      setState(() {
        statusMessage = 'Verificando estado de la impresora...';
        debugText = 'Enviando comandos de estado...';
      });

      //final status = await usbPlugin.checkPrinterStatus(vendorId, productId);
      //await usbPlugin.printEscPos(vendorId, productId, [0x1B, 0x40]); // ESC @
      //await Future.delayed(Duration(milliseconds: 500));
      final printerStatus =
          await usbPlugin.getPrinterStatus(vendorId, productId, [16, 4, 1]);

      if (!printerStatus['success']) {
        log('Error de conexión: ${printerStatus['error']}');
        log('La impresora parece estar apagada o desconectada');
        return; // No seguir intentando si hay un error fundamental de conexión
      }

      log('Estado de la impresora: $printerStatus');
      log('¿Impresora en línea? ${printerStatus['isOnline']}');

      // Verificar estado de la tapa solo si la impresora está conectada
      if (printerStatus['success']) {
        final coverStatus =
            await usbPlugin.getPrinterStatus(vendorId, productId, [16, 4, 2]);
        if (coverStatus['success']) {
          log('¿Tapa abierta? ${coverStatus['isCoverOpen'] ? 'Sí' : 'No'}');
          log('Estado de la tapa: $coverStatus');
        } else {
          log('No se pudo determinar el estado de la tapa: ${coverStatus['error']}');
        }

        final paperStatus =
            await usbPlugin.getPrinterStatus(vendorId, productId, [16, 4, 4]);

        if (paperStatus['success'] && paperStatus.containsKey('paperStatus')) {
          var paper = paperStatus['paperStatus'];
          if (paper['paperPresent']) {
            log('Hay papel en la impresora');
            log(paper['paperNearEnd']
                ? 'ADVERTENCIA: El papel está por acabarse'
                : 'La cantidad de papel es adecuada');
          } else {
            log('ERROR: No hay papel en la impresora');
          }
setState(() {
          paperOut = paper['paperPresent'];
          paperNearEnd = paper['paperNearEnd'];
          });
        } else {
          log('No se pudo determinar el estado del papel: ${paperStatus['error'] ?? 'Error desconocido'}');
        }

        setState(() {
          isOnline = printerStatus['isOnline'];
          coverOpen = coverStatus['isCoverOpen'];
          // Guardar información de depuración
          debugText = printerStatus['error'] ??
              'No se recibió información de depuración';

          statusMessage =
              'Estado actualizado. Revisa la sección de depuración.';
        });

        print("Respuesta 1: $printerStatus");
        print("Respuesta 2: $coverStatus");
        print("Respuesta 3: $paperStatus");
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Error al verificar estado: $e';
        debugText = 'Excepción: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba de Impresora'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Estado de la inicialización
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado del sistema:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Inicializado: ${isInitialized ? "Sí" : "No"}'),
                      const SizedBox(height: 4),
                      Text('Mensaje: $statusMessage'),
                      const SizedBox(height: 16),
                      ExpansionTile(
                        title: const Text('Información de depuración'),
                        initiallyExpanded: true,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8.0),
                            color: Colors.black,
                            width: double.infinity,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                debugText,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Estado de la impresora
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado de la impresora:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _StatusIndicator(
                              label: 'En línea',
                              isActive: isOnline,
                              positiveColor: Colors.green,
                            ),
                          ),
                          Expanded(
                            child: _StatusIndicator(
                              label: 'Sin papel',
                              isActive: paperOut,
                              positiveColor: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _StatusIndicator(
                              label: 'Tapa abierta',
                              isActive: coverOpen,
                              positiveColor: Colors.orange,
                            ),
                          ),
                          Expanded(
                            child: _StatusIndicator(
                              label: 'Poco papel',
                              isActive: paperNearEnd,
                              positiveColor: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Botones de acción
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: isInitialized ? _checkPrinterStatus : null,
                    child: const Text('Verificar Estado'),
                  ),
                  ElevatedButton(
                    onPressed: isInitialized ? _printTestTicket : null,
                    child: const Text('Imprimir Ticket'),
                  ),
                ],
              ),

              // Configuración de la impresora
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuración de la impresora:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Vendor ID: 0x${vendorId.toRadixString(16)}'),
                      Text('Product ID: 0x${productId.toRadixString(16)}'),
                      Text('Modelo: RPT-008 de 3nstar'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Widget para mostrar indicadores de estado
class _StatusIndicator extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color positiveColor;

  const _StatusIndicator({
    required this.label,
    required this.isActive,
    this.positiveColor = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isActive ? Icons.check_circle : Icons.cancel,
          color: isActive ? positiveColor : Colors.grey,
        ),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }
}

/*void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  print("Iniciando aplicación USB");
  
  // Pausa más larga para asegurar que el depurador está conectado
  await Future.delayed(Duration(seconds: 3));
  
  // Crear instancia del plugin
  final usbPlugin = UsbPlugin();
  print("Plugin USB instanciado");
  
  // Inicializar la librería
  try {
    final initResult = usbPlugin.initLibUsb();
    if (initResult < 0) {
      print("Error al inicializar libusb: $initResult");
      return;
    }
    print("libusb inicializado correctamente");
  } catch (e) {
    print("Excepción al inicializar libusb: $e");
    return;
  }
  
  try {
    // Obtener lista de dispositivos de forma más segura
    print("Intentando obtener lista de dispositivos...");
    List<UsbDeviceInfo> devices = [];
    
    try {
      devices = usbPlugin.getDetailedDeviceList();
      print("Dispositivos encontrados: ${devices.length}");
    } catch (e) {
      print("Error al obtener lista de dispositivos: $e");
      return;
    }
    
    // Procesar dispositivos en lotes pequeños con pausas
    int batchSize = 2;  // Procesar solo 2 dispositivos a la vez
    
    for (int i = 0; i < devices.length; i += batchSize) {
      print("Procesando lote ${i ~/ batchSize + 1}...");
      
      int endIndex = (i + batchSize < devices.length) ? i + batchSize : devices.length;
      
      for (int j = i; j < endIndex; j++) {
        final device = devices[j];
        
        // Imprimir información básica
        print('Dispositivo $j - productId: 0x${device.productId.toRadixString(16)} - vendorId: 0x${device.vendorId.toRadixString(16)}');
        
        // Evitar procesar la impresora problemática hasta el final
        if (device.vendorId == 0x067b && device.productId == 0x2305) {
          print("Impresora detectada - procesamiento pospuesto");
          continue;
        }
      }
      
      // Pausa entre lotes
      await Future.delayed(Duration(seconds: 1));
      print("Lote ${i ~/ batchSize + 1} completado");
    }
    
    // Imprimir información de resumen
    print("Resumen de dispositivos encontrados:");
    for (int i = 0; i < devices.length; i++) {
      final device = devices[i];
      print('${i+1}. VendorID: 0x${device.vendorId.toRadixString(16)}, ProductID: 0x${device.productId.toRadixString(16)}, Bus: ${device.busNumber}, Dirección: ${device.deviceAddress}');
    }
    
    // Al final, intentar procesar la impresora por separado con manejo de errores específico
    print("Buscando dispositivo de impresora...");
    UsbDeviceInfo? printerDevice;
    
    for (final device in devices) {
      if (device.vendorId == 0x067b && device.productId == 0x2305) {
        printerDevice = device;
        break;
      }
    }
    
    if (printerDevice != null) {
      print("Impresora encontrada - Información básica:");
      print("Bus: ${printerDevice.busNumber}");
      print("Dirección: ${printerDevice.deviceAddress}");
      print("Clase: 0x${printerDevice.deviceClass.toRadixString(16)}");
      
      print("Terminando sin intentar obtener detalles avanzados para prevenir crash");
    } else {
      print("Impresora no encontrada en esta ejecución");
    }
    
  } catch (e) {
    print("Error durante el procesamiento: $e");
  } finally {
    try {
      // Cerrar la librería cuando termines
      print("Cerrando libusb...");
      usbPlugin.exitLibUsb();
      print("libusb cerrado correctamente");
    } catch (e) {
      print("Error al cerrar libusb: $e");
    }
  }
  
  print("Programa finalizado");
}*/
