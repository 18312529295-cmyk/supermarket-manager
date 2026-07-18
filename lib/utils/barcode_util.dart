class BarcodeUtil {
  static bool isEAN13(String barcode) {
    if (barcode.length != 13) return false;
    if (!RegExp(r'^\d{13}$').hasMatch(barcode)) return false;
    return _validateEANChecksum(barcode);
  }

  static bool isEAN8(String barcode) {
    if (barcode.length != 8) return false;
    if (!RegExp(r'^\d{8}$').hasMatch(barcode)) return false;
    return _validateEANChecksum(barcode);
  }

  static bool isUPCA(String barcode) {
    if (barcode.length != 12) return false;
    if (!RegExp(r'^\d{12}$').hasMatch(barcode)) return false;
    return _validateUPCAChecksum(barcode);
  }

  static bool isCode128(String barcode) {
    return RegExp(r'^[\x00-\x7F]+$').hasMatch(barcode);
  }

  static bool isLocalUzbekBarcode(String barcode) {
    // Uzbekistan often uses 478 (GS1 prefix) or local internal codes
    if (barcode.length >= 13 && barcode.startsWith('478')) return true;
    // Internal codes often 8-10 digits without standard checksum
    if (barcode.length >= 6 && barcode.length <= 10 && RegExp(r'^\d+$').hasMatch(barcode)) {
      return true;
    }
    return false;
  }

  static bool isValidBarcode(String barcode) {
    if (barcode.isEmpty) return false;
    return isEAN13(barcode) ||
        isEAN8(barcode) ||
        isUPCA(barcode) ||
        isCode128(barcode) ||
        isLocalUzbekBarcode(barcode);
  }

  static String detectFormat(String barcode) {
    if (isEAN13(barcode)) return 'EAN-13';
    if (isEAN8(barcode)) return 'EAN-8';
    if (isUPCA(barcode)) return 'UPC-A';
    if (isLocalUzbekBarcode(barcode)) return 'Local';
    if (isCode128(barcode)) return 'CODE-128';
    return 'Unknown';
  }

  static bool _validateEANChecksum(String barcode) {
    int sum = 0;
    for (int i = 0; i < barcode.length - 1; i++) {
      int digit = int.parse(barcode[i]);
      if (i % 2 == barcode.length % 2) {
        sum += digit * 3;
      } else {
        sum += digit;
      }
    }
    int checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(barcode[barcode.length - 1]);
  }

  static bool _validateUPCAChecksum(String barcode) {
    int sum = 0;
    for (int i = 0; i < barcode.length - 1; i++) {
      int digit = int.parse(barcode[i]);
      if (i % 2 == 0) {
        sum += digit * 3;
      } else {
        sum += digit;
      }
    }
    int checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(barcode[barcode.length - 1]);
  }

  static String? normalizeBarcode(String raw) {
    String cleaned = raw.trim();
    // Remove common prefix/suffix control characters from scanners
    if (cleaned.startsWith(']C1')) cleaned = cleaned.substring(3);
    // Keep only printable ASCII
    cleaned = cleaned.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }
}
