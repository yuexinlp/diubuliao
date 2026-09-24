import 'voice_contact_draft.dart';

enum VoiceCommandType { call, search, create, unknown }

class VoiceCommand {
  const VoiceCommand(this.type, this.value, {this.contactDraft});

  final VoiceCommandType type;
  final String value;
  final VoiceContactDraft? contactDraft;
}

class VoiceCommandParser {
  static VoiceCommand parse(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const VoiceCommand(VoiceCommandType.unknown, '');
    }

    final callFirstMatch = RegExp(
      r'^(?:请)?(?:打电话|拨电话|拨打电话)给(.+)$',
    ).firstMatch(text);
    if (callFirstMatch != null) {
      return VoiceCommand(
        VoiceCommandType.call,
        _cleanValue(callFirstMatch.group(1)!),
      );
    }

    final callMatch = RegExp(
      r'^(?:请)?(?:给|帮我给|拨打|呼叫)(.+?)(?:打电话|拨电话|电话|拨号)?$',
    ).firstMatch(text);
    if (callMatch != null) {
      return VoiceCommand(
        VoiceCommandType.call,
        _cleanValue(callMatch.group(1)!),
      );
    }

    final createMatch = RegExp(
      r'^(?:请)?(?:新增|新建|添加|创建)(?:一个)?联系人(?:叫|是|为)?(.+)$',
    ).firstMatch(text);
    if (createMatch != null) {
      final draft = VoiceContactDraftParser.parse(text);
      final name = draft == null || draft.name.isEmpty
          ? _cleanValue(createMatch.group(1)!)
          : draft.name;
      return VoiceCommand(
        VoiceCommandType.create,
        name,
        contactDraft: draft,
      );
    }

    final searchMatch = RegExp(
      r'^(?:请)?(?:查询|搜索|找一下|找)(.+)$',
    ).firstMatch(text);
    if (searchMatch != null) {
      return VoiceCommand(
        VoiceCommandType.search,
        _cleanValue(searchMatch.group(1)!),
      );
    }

    return VoiceCommand(VoiceCommandType.search, text);
  }

  static String _cleanValue(String value) => value
      .trim()
      .replaceFirst(RegExp(r'[，。！？!?、]+$'), '')
      .trim();
}
