double? parseAmount(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return double.tryParse(raw.trim().replaceAll(',', '.'));
}
