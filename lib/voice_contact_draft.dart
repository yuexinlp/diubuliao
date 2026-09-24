import 'voice_matching.dart';

class VoiceContactDraft {
  const VoiceContactDraft({
    required this.name,
    required this.phone,
    this.category = '',
    this.remark = '',
  });

  final String name;
  final String phone;
  final String category;
  final String remark;

  String get phoneDigits => spokenPhoneDigits(phone);
  String? get normalizedMobile => mainlandMobileDigits(phone);
  bool get hasValidMobile => normalizedMobile != null;
}

class VoiceContactDraftParser {
  static VoiceContactDraft? parse(String input) {
    final text = input.trim();
    final prefix = RegExp(
      r'^(?:请)?(?:新增|添加|新建|创建)(?:一个)?联系人',
    ).firstMatch(text);
    if (prefix == null) return null;

    final body = text.substring(prefix.end).trim();
    final fieldPattern = RegExp(
      r'(姓名|手机号码|手机号|电话号码|电话|分类|备注)\s*[:：]?\s*'
      r'(.*?)(?=(?:姓名|手机号码|手机号|电话号码|电话|分类|备注)\s*[:：]?|[，,；;\n]|$)',
    );
    final fields = <String, String>{};
    final matches = fieldPattern.allMatches(body).toList(growable: false);
    for (final match in matches) {
      fields[match.group(1)!] = _clean(match.group(2)!);
    }

    final phone = fields['手机号码'] ??
        fields['手机号'] ??
        fields['电话号码'] ??
        fields['电话'] ??
        _findPhone(body);
    final name = fields['姓名'] ??
        (matches.isEmpty
            ? _clean(body)
            : _clean(body.substring(0, matches.first.start)));

    return VoiceContactDraft(
      name: name,
      phone: phone,
      category: fields['分类'] ?? '',
      remark: fields['备注'] ?? '',
    );
  }

  static String _findPhone(String value) {
    final arabic = RegExp(r'(?<!\d)1[3-9][\d\s-]{9,}');
    final chinese = RegExp(
      r'(?:[零〇洞一幺二两俩三四五六七拐八九勾][\s-]*){11,}',
    );
    return _clean(
      arabic.firstMatch(value)?.group(0) ??
          chinese.firstMatch(value)?.group(0) ??
          '',
    );
  }

  static String _clean(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^[，,；;：:。\s]+'), '')
      .replaceFirst(RegExp(r'[，,；;：:。\s]+$'), '')
      .trim();
}
