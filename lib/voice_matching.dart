class VoiceContactCandidate {
  const VoiceContactCandidate({
    required this.name,
    required this.phone,
    this.searchText = '',
  });

  final String name;
  final String phone;
  final String searchText;
}

class VoiceContactMatcher {
  static VoiceContactCandidate? findBest(
    String input,
    Iterable<VoiceContactCandidate> contacts,
  ) {
    final candidates = contacts.toList(growable: false);
    final query = _normalizeText(input);
    if (query.isEmpty) return null;

    final phoneQuery = spokenPhoneDigits(input);
    if (phoneQuery.length >= 5) {
      final phoneMatches = candidates
          .where((contact) {
            final phone = spokenPhoneDigits(contact.phone);
            return phone.contains(phoneQuery) || phoneQuery.contains(phone);
          })
          .toList(growable: false);
      if (phoneMatches.length == 1) return phoneMatches.single;
      if (phoneMatches.length > 1) return null;
    }

    final nameMatches = candidates
        .where((contact) => _normalizeText(contact.name) == query)
        .toList(growable: false);
    if (nameMatches.length == 1) return nameMatches.single;
    if (nameMatches.length > 1) return null;

    final phoneticQuery = _phoneticKey(query);
    final phoneticMatches = candidates
        .where((contact) => _phoneticKey(contact.name) == phoneticQuery)
        .toList(growable: false);
    if (phoneticMatches.length == 1) return phoneticMatches.single;
    if (phoneticMatches.length > 1) return null;

    final containsMatches = candidates
        .where((contact) {
          final name = _normalizeText(contact.name);
          final phoneticName = _phoneticKey(name);
          return name.contains(query) ||
              query.contains(name) ||
              phoneticName.contains(phoneticQuery) ||
              phoneticQuery.contains(phoneticName);
        })
        .toList(growable: false);
    if (containsMatches.length == 1) return containsMatches.single;
    if (containsMatches.length > 1) return null;

    if (query.runes.length < 2) return null;
    final scored = candidates
        .map(
          (contact) => _ScoredContact(
            contact,
            _distance(
              query.runes.toList(),
              _normalizeText(contact.name).runes.toList(),
            ),
          ),
        )
        .where((item) => item.distance <= _maxDistance(query.runes.length))
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    if (scored.isEmpty) return null;
    if (scored.length > 1 && scored[0].distance == scored[1].distance) {
      return null;
    }
    return scored.first.contact;
  }

  static bool hasSearchMatch(
    String input,
    Iterable<VoiceContactCandidate> contacts,
  ) {
    final candidates = contacts.toList(growable: false);
    final query = _normalizeText(input);
    if (query.isEmpty) return false;
    return candidates.any((contact) => matchesSearch(input, contact));
  }

  static bool matchesSearch(
    String input,
    VoiceContactCandidate contact,
  ) {
    final query = _normalizeText(input);
    if (query.isEmpty) return false;
    final searchText = _normalizeText(
      contact.searchText.isEmpty
          ? '${contact.name}${contact.phone}'
          : contact.searchText,
    );
    if (searchText.contains(query)) return true;

    final phoneQuery = spokenPhoneDigits(input);
    final phone = spokenPhoneDigits(contact.phone);
    if (phoneQuery.length >= 5 && phone.contains(phoneQuery)) return true;

    final phoneticQuery = _phoneticKey(query);
    final phoneticName = _phoneticKey(contact.name);
    if (phoneticName.contains(phoneticQuery) ||
        phoneticQuery.contains(phoneticName)) {
      return true;
    }
    if (query.runes.length < 2) return false;
    return _distance(
          query.runes.toList(),
          _normalizeText(contact.name).runes.toList(),
        ) <=
        _maxDistance(query.runes.length);
  }

  static String? displaySearchQuery(
    String input,
    Iterable<VoiceContactCandidate> contacts,
  ) {
    final candidates = contacts.toList(growable: false);
    if (!hasSearchMatch(input, candidates)) return null;
    final mobile = mainlandMobileDigits(input);
    if (mobile != null) return mobile;
    return findBest(input, candidates)?.name ?? input;
  }

  static String _normalizeText(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s,，。！？!?、：:；;（）()\-]'), '');

  static const _homophoneGroups = <String, String>{
    'shi': '石食实十时识',
    'yan': '岩盐言严沿研',
    'san': '三山杉珊姗',
    'zhang': '张章',
    'li': '李礼里理',
    'jian': '健建剑见',
    'xue': '薛学雪',
    'yuan': '元原园圆源',
    'bao': '宝保饱',
    'liu': '刘六留流',
    'chen': '陈沉晨',
    'wang': '王网旺',
    'yang': '杨阳洋扬',
    'zhou': '周州洲',
    'zhao': '赵照兆',
    'wu': '吴无',
    'gao': '高糕',
    'ming': '明名铭',
    'lin': '林琳霖',
    'jun': '俊君军',
    'jie': '杰洁结',
    'wen': '文闻',
    'hua': '华花',
    'qiang': '强墙',
    'ning': '宁凝',
    'xiang': '祥翔',
  };

  static String _phoneticKey(String value) {
    final key = StringBuffer();
    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      var syllable = character;
      for (final group in _homophoneGroups.entries) {
        if (group.value.contains(character)) {
          syllable = group.key;
          break;
        }
      }
      key.write(syllable);
    }
    return key.toString();
  }

  static int _maxDistance(int length) =>
      (length * 0.34).floor().clamp(1, 3);

  static int _distance(List<int> a, List<int> b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final substitution = a[i] == b[j] ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + substitution,
        ].reduce((left, right) => left < right ? left : right);
      }
      previous = current;
    }
    return previous.last;
  }
}

class _ScoredContact {
  const _ScoredContact(this.contact, this.distance);

  final VoiceContactCandidate contact;
  final int distance;
}

String spokenPhoneDigits(String value) {
  const digitMap = {
    '零': '0',
    '〇': '0',
    '洞': '0',
    '一': '1',
    '幺': '1',
    '二': '2',
    '两': '2',
    '俩': '2',
    '三': '3',
    '四': '4',
    '五': '5',
    '六': '6',
    '七': '7',
    '拐': '7',
    '八': '8',
    '九': '9',
    '勾': '9',
  };
  final digits = StringBuffer();
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    if (rune >= 48 && rune <= 57) {
      digits.write(character);
    } else {
      final digit = digitMap[character];
      if (digit != null) digits.write(digit);
    }
  }
  var result = digits.toString();
  if (result.startsWith('0086')) result = result.substring(4);
  if (result.startsWith('86') && result.length >= 12) {
    result = result.substring(2);
  }
  return result;
}

String? mainlandMobileDigits(String value) {
  final digits = spokenPhoneDigits(value);
  return RegExp(r'^1[3-9]\d{9}$').hasMatch(digits) ? digits : null;
}
