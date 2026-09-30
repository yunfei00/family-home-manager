class FastEntryDraft {
  const FastEntryDraft({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final double quantity;
  final String unit;
}

List<FastEntryDraft> parseFastEntries(String input) {
  final chunks = input
      .split(RegExp(r'[\n，,、；;]+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty);

  return [
    for (final chunk in chunks)
      if (_parseChunk(chunk) case final draft?) draft,
  ];
}

FastEntryDraft? _parseChunk(String chunk) {
  final pattern = RegExp(
    r'^(.*?)(?:\s*[xX×]?\s*)'
    r'(\d+(?:\.\d+)?|[零〇一二两三四五六七八九十]+)'
    r'\s*(个|件|支|盒|包|瓶|袋|套|箱|卷|本|把|台|双|条|张|只|桶|罐)?$',
  );
  final match = pattern.firstMatch(chunk);

  if (match == null) {
    return FastEntryDraft(name: chunk, quantity: 1, unit: '个');
  }

  final rawName = (match.group(1) ?? '').trim();
  if (rawName.isEmpty) {
    return FastEntryDraft(name: chunk, quantity: 1, unit: '个');
  }

  final rawQuantity = match.group(2)!;
  final quantity = double.tryParse(rawQuantity) ?? _parseChineseNumber(rawQuantity);
  if (quantity == null) {
    return FastEntryDraft(name: chunk, quantity: 1, unit: '个');
  }

  return FastEntryDraft(
    name: rawName,
    quantity: quantity,
    unit: match.group(3) ?? '个',
  );
}

double? _parseChineseNumber(String value) {
  const digits = <String, int>{
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };

  if (value == '十') return 10;
  if (value.contains('十')) {
    final parts = value.split('十');
    if (parts.length != 2) return null;

    final tens = parts.first.isEmpty ? 1 : digits[parts.first];
    final ones = parts.last.isEmpty ? 0 : digits[parts.last];
    if (tens == null || ones == null) return null;
    return (tens * 10 + ones).toDouble();
  }

  final digit = digits[value];
  return digit?.toDouble();
}
