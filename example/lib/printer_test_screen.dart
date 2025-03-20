import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:usb_plugins_printer/usb_plugins.dart';

class PrinterTestScreen extends StatefulWidget {
  const PrinterTestScreen({super.key});

  @override
  State<PrinterTestScreen> createState() => _PrinterTestScreenState();
}

class _PrinterTestScreenState extends State<PrinterTestScreen> {
  final UsbPlugin usbPlugin = UsbPlugin();
  bool isInitialized = false;
  String statusMessage = "Not initialized";
  String debugText = '';

  // Printer IDs
  final int vendorId = 0x067b;
  final int productId = 0x2305;

  // Printer status results
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
      usbPlugin.exitUsbLibrary();
    }
    super.dispose();
  }

  Future<void> _initializeUsbPlugin() async {
    final initResult = usbPlugin.initUsbLibrary();
    if (initResult != 0) {
      setState(() {
        statusMessage = 'Error initializing libusb: $initResult';
        isInitialized = false;
      });
      return;
    }

    setState(() {
      statusMessage = 'USB library initialized successfully';
      isInitialized = true;
    });
  }

  Future<void> _printTestTicket() async {
    if (!isInitialized) {
      setState(() {
        statusMessage = 'USB not initialized. Initialize first.';
      });
      return;
    }

    try {
      setState(() {
        statusMessage = 'Sending data to printer...';
      });

      // ESC/POS commands for the test ticket
      final List<int> commands = [
        0x1B, 0x40, // Initialize printer

        // Header - Centered
        0x1B, 0x61, 0x01, // Center
        ...utf8.encode('My Store\n'),
        ...utf8.encode('Main Ave 123\n'),
        ...utf8.encode('Tel: 555-1234\n'),
        0x1B, 0x64, 0x01, // Spacing

        // Separator line
        ...utf8.encode('------------------------------\n'),

        // Ticket details (Left)
        0x1B, 0x61, 0x00, // Align left
        ...utf8.encode('Qty  Description    Price\n'),
        ...utf8.encode('--------------------------------\n'),
        ...utf8.encode(' 1   Product A      \$10.00\n'),
        ...utf8.encode(' 2   Product B      \$20.00\n'),
        ...utf8.encode(' 1   Product C      \$15.00\n'),

        // Subtotal and total
        ...utf8.encode('------------------------------\n'),
        0x1B, 0x61, 0x02, // Align right
        ...utf8.encode('Subtotal:       \$45.00\n'),
        ...utf8.encode('VAT (21%):      \$9.45\n'),
        ...utf8.encode('Total:          \$54.45\n'),

        // Spacing and final message
        0x1B, 0x64, 0x02, // Advance 2 lines
        0x1B, 0x61, 0x01, // Center
        ...utf8.encode('Thank you for your purchase!\n'),

        0x1B, 0x64, 0x03, // Advance 3 lines
        0x1D, 0x56, 0x00, // Paper cut
      ];

      // Send commands to the printer
      final result = await usbPlugin.printEscPos(vendorId, productId, commands);

      if (result['success'] == true) {
        setState(() {
          statusMessage =
              'Data sent successfully: ${result['bytesSent']} bytes';
        });
      } else {
        setState(() {
          statusMessage = 'Error sending data: ${result['error']}';
          if (result.containsKey('errorCode')) {
            statusMessage += '\nError code: ${result['errorCode']}';
          }
        });
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Exception: $e';
      });
    }
  }

  Future<void> _checkPrinterStatus() async {
    if (!isInitialized) {
      setState(() {
        statusMessage = 'USB not initialized. Initialize first.';
      });
      return;
    }

    try {
      setState(() {
        statusMessage = 'Checking printer status...';
        debugText = 'Sending status commands...';
      });

      //final status = await usbPlugin.checkPrinterStatus(vendorId, productId);
      //await usbPlugin.printEscPos(vendorId, productId, [0x1B, 0x40]); // ESC @
      //await Future.delayed(Duration(milliseconds: 500));
      final printerStatus =
          await usbPlugin.getPrinterStatus(vendorId, productId, [16, 4, 1]);

      if (!printerStatus['success']) {
        log('Connection error: ${printerStatus['error']}');
        log('The printer appears to be off or disconnected');
        return; // Do not continue if there is a fundamental connection error
      }

      log('Printer status: $printerStatus');
      log('Is printer online? ${printerStatus['isOnline']}');

      // Check cover status only if the printer is connected
      if (printerStatus['success']) {
        final coverStatus =
            await usbPlugin.getPrinterStatus(vendorId, productId, [16, 4, 2]);
        if (coverStatus['success']) {
          log('Is cover open? ${coverStatus['isCoverOpen'] ? 'Yes' : 'No'}');
          log('Cover status: $coverStatus');
        } else {
          log('Could not determine cover status: ${coverStatus['error']}');
        }

        final paperStatus =
            await usbPlugin.getPrinterStatus(vendorId, productId, [16, 4, 4]);

        if (paperStatus['success'] && paperStatus.containsKey('paperStatus')) {
          var paper = paperStatus['paperStatus'];
          if (paper['paperPresent']) {
            log('There is paper in the printer');
            log(paper['paperNearEnd']
                ? 'WARNING: Paper is running low'
                : 'Paper quantity is adequate');
          } else {
            log('ERROR: No paper in the printer');
          }
          setState(() {
            paperOut = !paper['paperPresent'];
            paperNearEnd = paper['paperNearEnd'];
          });
        } else {
          log('Could not determine paper status: ${paperStatus['error'] ?? 'Unknown error'}');
        }

        setState(() {
          isOnline = printerStatus['isOnline'];
          coverOpen = coverStatus['isCoverOpen'];
          // Save debug information
          debugText = printerStatus['error'] ?? 'No debug information received';

          statusMessage = 'Status updated. Check the debug section.';
        });

        print("Response 1: $printerStatus");
        print("Response 2: $coverStatus");
        print("Response 3: $paperStatus");
      }
    } catch (e) {
      setState(() {
        statusMessage = 'Error checking status: $e';
        debugText = 'Exception: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Initialization status
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'System Status:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Initialized: ${isInitialized ? "Yes" : "No"}'),
                      const SizedBox(height: 4),
                      Text('Message: $statusMessage'),
                      const SizedBox(height: 16),
                      ExpansionTile(
                        title: const Text('Debug Information'),
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

              // Printer status
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Printer Status:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _StatusIndicator(
                              label: 'Online',
                              isActive: isOnline,
                              positiveColor: Colors.green,
                            ),
                          ),
                          Expanded(
                            child: _StatusIndicator(
                              label: 'Paper Out',
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
                              label: 'Cover Open',
                              isActive: coverOpen,
                              positiveColor: Colors.orange,
                            ),
                          ),
                          Expanded(
                            child: _StatusIndicator(
                              label: 'Paper Low',
                              isActive: paperNearEnd,
                              positiveColor: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: isInitialized ? _checkPrinterStatus : null,
                    child: const Text('Check Status'),
                  ),
                  ElevatedButton(
                    onPressed: isInitialized ? _printTestTicket : null,
                    child: const Text('Print Ticket'),
                  ),
                ],
              ),

              // Printer configuration
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Printer Configuration:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Vendor ID: 0x${vendorId.toRadixString(16)}'),
                      Text('Product ID: 0x${productId.toRadixString(16)}'),
                      Text('Model: 3nstar RPT-008'),
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

// Widget for displaying status indicators
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

  print("Starting USB application");

  // Longer pause to ensure the debugger is connected
  await Future.delayed(Duration(seconds: 3));

  // Create plugin instance
  final usbPlugin = UsbPlugin();
  print("USB Plugin instantiated");

  // Initialize the library
  try {
    final initResult = usbPlugin.initLibUsb();
    if (initResult < 0) {
      print("Error initializing libusb: $initResult");
      return;
    }
    print("libusb initialized successfully");
  } catch (e) {
    print("Exception initializing libusb: $e");
    return;
  }

  try {
    // Get device list more safely
    print("Attempting to get device list...");
    List<UsbDeviceInfo> devices = [];

    try {
      devices = usbPlugin.getDetailedDeviceList();
      print("Devices found: ${devices.length}");
    } catch (e) {
      print("Error getting device list: $e");
      return;
    }

    // Process devices in small batches with pauses
    int batchSize = 2; // Process only 2 devices at a time

    for (int i = 0; i < devices.length; i += batchSize) {
      print("Processing batch ${i ~/ batchSize + 1}...");

      int endIndex = (i + batchSize < devices.length) ? i + batchSize : devices.length;

      for (int j = i; j < endIndex; j++) {
        final device = devices[j];

        // Print basic information
        print('Device $j - productId: 0x${device.productId.toRadixString(16)} - vendorId: 0x${device.vendorId.toRadixString(16)}');

        // Avoid processing the problematic printer until the end
        if (device.vendorId == 0x067b && device.productId == 0x2305) {
          print("Printer detected - processing postponed");
          continue;
        }
      }

      // Pause between batches
      await Future.delayed(Duration(seconds: 1));
      print("Batch ${i ~/ batchSize + 1} completed");
    }

    // Print summary information
    print("Summary of devices found:");
    for (int i = 0; i < devices.length; i++) {
      final device = devices[i];
      print('${i+1}. VendorID: 0x${device.vendorId.toRadixString(16)}, ProductID: 0x${device.productId.toRadixString(16)}, Bus: ${device.busNumber}, Address: ${device.deviceAddress}');
    }

    // At the end, try to process the printer separately with specific error handling
    print("Searching for printer device...");
    UsbDeviceInfo? printerDevice;

    for (final device in devices) {
      if (device.vendorId == 0x067b && device.productId == 0x2305) {
        printerDevice = device;
        break;
      }
    }

    if (printerDevice != null) {
      print("Printer found - Basic information:");
      print("Bus: ${printerDevice.busNumber}");
      print("Address: ${printerDevice.deviceAddress}");
      print("Class: 0x${printerDevice.deviceClass.toRadixString(16)}");

      print("Terminating without attempting to get advanced details to prevent crash");
    } else {
      print("Printer not found in this execution");
    }
  } catch (e) {
    print("Error during processing: $e");
  } finally {
    try {
      // Close the library when finished
      print("Closing libusb...");
      usbPlugin.exitLibUsb();
      print("libusb closed successfully");
    } catch (e) {
      print("Error closing libusb: $e");
    }
  }

  print("Program finished");
}*/
