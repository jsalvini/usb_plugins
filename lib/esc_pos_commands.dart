// Clase auxiliar para generar comandos ESC/POS comunes
import 'dart:convert';
import 'dart:typed_data';

class EscPosCommands {
  // Comandos de formato de texto
  static List<int> text(String text) {
    return utf8.encode(text);
  }

  static List<int> bold(bool on) {
    // ESC E n - Activar/desactivar énfasis (negrita)
    return [0x1B, 0x45, on ? 1 : 0];
  }

  static List<int> underline(int weight) {
    // ESC - n - Activar/desactivar subrayado (0-2)
    return [0x1B, 0x2D, weight.clamp(0, 2)];
  }

  static List<int> fontSize(int width, int height) {
    // GS ! n - Seleccionar tamaño de caracteres
    int size = (width.clamp(1, 8) - 1) | ((height.clamp(1, 8) - 1) << 4);
    return [0x1D, 0x21, size];
  }

  static List<int> align(int alignment) {
    // ESC a n - Seleccionar justificación (0: izquierda, 1: centro, 2: derecha)
    return [0x1B, 0x61, alignment.clamp(0, 2)];
  }

  // Comandos de control de papel
  static List<int> feed(int lines) {
    // ESC d n - Avanzar n líneas
    return [0x1B, 0x64, lines.clamp(0, 255)];
  }

  static List<int> cut() {
    // GS V - Cortar papel
    return [0x1D, 0x56, 0x00];
  }

  static List<int> partialCut() {
    // GS V - Corte parcial
    return [0x1D, 0x56, 0x01];
  }

  // Comandos de imágenes
  static List<int> image(Uint8List imageData, int width, int mode) {
    // Este es un ejemplo simplificado. La implementación real dependerá
    // del formato específico de imagen y cómo la impresora lo procesa.
    List<int> commands = [];

    // Comando GS v 0 - Impresión de mapa de bits
    commands.add(0x1D);
    commands.add(0x76);
    commands.add(0x30);
    commands.add(mode); // Modo (0-3)

    // Ancho en bytes (cada byte = 8 píxeles horizontales)
    int widthBytes = (width + 7) ~/ 8;
    commands.add(widthBytes & 0xFF);
    commands.add((widthBytes >> 8) & 0xFF);

    // Alto en píxeles
    int height = imageData.length ~/ widthBytes;
    commands.add(height & 0xFF);
    commands.add((height >> 8) & 0xFF);

    // Datos de la imagen
    commands.addAll(imageData);

    return commands;
  }

  // Comandos de código de barras
  static List<int> barcode(
      String data, int type, int height, int width, int position, int font) {
    List<int> commands = [];

    // GS h - Altura del código de barras
    commands.addAll([0x1D, 0x68, height.clamp(1, 255)]);

    // GS w - Ancho del código de barras
    commands.addAll([0x1D, 0x77, width.clamp(2, 6)]);

    // GS H - Posición del texto HRI
    commands.addAll([0x1D, 0x48, position.clamp(0, 3)]);

    // GS f - Fuente del texto HRI
    commands.addAll([0x1D, 0x66, font.clamp(0, 1)]);

    // GS k - Imprimir código de barras
    commands.addAll([0x1D, 0x6B, type.clamp(0, 73)]);

    // Longitud y datos (depende del tipo de código de barras)
    if (type >= 65 && type <= 73) {
      // Tipos 65-73 usan un formato diferente
      List<int> dataBytes = utf8.encode(data);
      commands.add(dataBytes.length);
      commands.addAll(dataBytes);
    } else {
      // Tipos 0-6 terminan con NUL
      commands.addAll(utf8.encode(data));
      commands.add(0x00);
    }

    return commands;
  }

  // Comandos de QR Code
  static List<int> qrCode(String data, int size, int errorCorrection) {
    List<int> commands = [];

    // Modelo de QR
    commands.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

    // Tamaño del módulo
    commands
        .addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.clamp(1, 16)]);

    // Nivel de corrección de errores
    commands.addAll([
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x45,
      errorCorrection.clamp(0, 3)
    ]);

    // Datos
    List<int> dataBytes = utf8.encode(data);
    int dataLength = dataBytes.length + 3;
    commands.addAll([
      0x1D,
      0x28,
      0x6B,
      dataLength & 0xFF,
      (dataLength >> 8) & 0xFF,
      0x31,
      0x50,
      0x30
    ]);
    commands.addAll(dataBytes);

    // Imprimir QR
    commands.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);

    return commands;
  }

  // Método para combinar múltiples comandos
  static List<int> combine(List<List<int>> commandsList) {
    List<int> combined = [];
    for (var cmd in commandsList) {
      combined.addAll(cmd);
    }
    return combined;
  }

  // Comandos comunes
  static List<int> initialize() {
    return [0x1B, 0x40]; // ESC @
  }

  static List<int> lineFeed() {
    return [0x0A]; // LF
  }

  static List<int> formFeed() {
    return [0x0C]; // FF
  }

  static List<int> carriageReturn() {
    return [0x0D]; // CR
  }

  static List<int> beep() {
    return [0x1B, 0x42, 0x05, 0x09]; // Beep 5 veces, 9*50ms por beep
  }

  static List<int> drawer(int pin, int onTime, int offTime) {
    // ESC p - Abrir cajón
    return [0x1B, 0x70, pin, onTime, offTime];
  }
}
