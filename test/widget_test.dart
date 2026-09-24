import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart' as gbk_codec;

import 'package:contact_atlas/main.dart';
import 'package:contact_atlas/local_voice.dart';
import 'package:contact_atlas/voice_matching.dart';
import 'package:contact_atlas/voice_session.dart';

void main() {
  testWidgets('shows the three primary areas', (WidgetTester tester) async {
    await tester.pumpWidget(const LostProofApp());
    await tester.pump();

    expect(find.text('数据中心'), findsWidgets);
    expect(find.text('联系人'), findsOneWidget);

    await tester.tap(find.text('联系人').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('添加联系人'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('数据操作'), findsOneWidget);
  });

  test('uses the bundled seven-digit phone attribution database', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await PhoneRegionDatabase.load();
    expect(phoneRegion('13800130000'), '北京');
    expect(phoneRegion('18957500000'), '浙江');
    expect(phoneRegion('19900000000'), '归属地待识别');
  });

  test('projects the complete China map without clipping its bounds', () {
    final map = ChinaMapData([
      ChinaProvince(
        name: 'test bounds',
        center: const Offset(104, 35),
        rings: [
          [
            const Offset(73.48, 18.1),
            const Offset(134.8, 18.1),
            const Offset(134.8, 53.35),
            const Offset(73.48, 53.35),
          ],
        ],
      ),
    ]);

    expect(map.x(73.48), lessThan(0.06));
    expect(map.x(134.8), greaterThan(0.94));
    expect(map.y(53.35), lessThan(0.12));
    expect(map.y(18.1), greaterThan(0.88));
  });

  test('parses UTF-8 quoted-printable vCards', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        'BEGIN:VCARD\r\n'
        'VERSION:3.0\r\n'
        'FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=E5=BC=A0=E4=B8=89\r\n'
        'TEL;TYPE=CELL:13800130000\r\n'
        'END:VCARD\r\n',
      ),
    );
    final result = VCardCodec.parseBytes(bytes);
    expect(result.single.name, '张三');
  });

  test('parses GBK vCards and folded fields', () {
    final bytes = Uint8List.fromList(
      gbk_codec.gbk_bytes.encode(
        'BEGIN:VCARD\r\n'
        'VERSION:3.0\r\n'
        'FN;CHARSET=GB18030:张三\r\n'
        'NOTE;CHARSET=GB18030:这是一个很长的备注\r\n'
        'TEL;TYPE=CELL:18957500000\r\n'
        'END:VCARD\r\n',
      ),
    );
    final result = VCardCodec.parseBytes(bytes);
    expect(result.single.name, '张三');
    expect(result.single.phone, '18957500000');
  });

  test('splits category and name from tilde-style vCards', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        'BEGIN:VCARD\r\n'
        'VERSION:3.0\r\n'
        'FN:家人~六三\r\n'
        'TEL;TYPE=CELL:13800130000\r\n'
        'END:VCARD\r\n',
      ),
    );
    final result = VCardCodec.parseBytes(bytes);
    expect(result.single.category, '家人');
    expect(result.single.name, '六三');
  });

  test('parses a call command into a contact name', () {
    final command = VoiceCommandParser.parse('给张三打电话');

    expect(command.type, VoiceCommandType.call);
    expect(command.value, '张三');
  });

  test('parses a call command when the action comes first', () {
    final command = VoiceCommandParser.parse('打电话给王五');

    expect(command.type, VoiceCommandType.call);
    expect(command.value, '王五');
  });

  test('parses a search command into a query', () {
    final command = VoiceCommandParser.parse('查询家人');

    expect(command.type, VoiceCommandType.search);
    expect(command.value, '家人');
  });

  test('treats a bare voice phrase as a search query', () {
    final command = VoiceCommandParser.parse('张山');

    expect(command.type, VoiceCommandType.search);
    expect(command.value, '张山');
  });

  test('parses a create command into a contact name', () {
    final command = VoiceCommandParser.parse('新增联系人李四');

    expect(command.type, VoiceCommandType.create);
    expect(command.value, '李四');
  });

  test('parses a structured voice contact draft', () {
    final command = VoiceCommandParser.parse(
      '添加联系人，姓名张三，手机号一三八零零零零零零零零，分类朋友，备注同事',
    );

    expect(command.type, VoiceCommandType.create);
    expect(command.value, '张三');
    expect(command.contactDraft?.name, '张三');
    expect(command.contactDraft?.phoneDigits, '13800000000');
    expect(command.contactDraft?.category, '朋友');
    expect(command.contactDraft?.remark, '同事');
  });

  test('does not treat an incomplete voice phone as valid', () {
    final command = VoiceCommandParser.parse(
      '新增联系人，姓名张三，手机号1380000',
    );

    expect(command.contactDraft?.name, '张三');
    expect(command.contactDraft?.hasValidMobile, isFalse);
  });

  test('parses voice contact fields without spoken punctuation', () {
    final command = VoiceCommandParser.parse(
      '新增联系人姓名张三 手机号13800000000 分类朋友 备注同事',
    );

    expect(command.contactDraft?.name, '张三');
    expect(command.contactDraft?.phoneDigits, '13800000000');
    expect(command.contactDraft?.category, '朋友');
    expect(command.contactDraft?.remark, '同事');
  });

  test('uses the bundled SenseVoice model files', () {
    expect(SenseVoiceModelPaths.modelAsset, endsWith('/model.int8.onnx'));
    expect(SenseVoiceModelPaths.tokensAsset, endsWith('/tokens.txt'));
  });

  test('converts Chinese spoken digits into a phone number', () {
    expect(spokenPhoneDigits('幺三八零零零零零零零零'), '13800000000');
  });

  test('matches a contact by a spoken phone number', () {
    final candidates = [
      const VoiceContactCandidate(name: '张三', phone: '13800000000'),
    ];
    final match = VoiceContactMatcher.findBest(
      '幺三八零零零零零零零零',
      candidates,
    );

    expect(match?.name, '张三');
    expect(
      VoiceContactMatcher.displaySearchQuery(
        '幺三八零零零零零零零零',
        candidates,
      ),
      '13800000000',
    );
  });

  test('fuzzy matches a recognition typo to a unique contact', () {
    final match = VoiceContactMatcher.findBest(
      '张山',
      [
        const VoiceContactCandidate(name: '张三', phone: '13800000000'),
      ],
    );

    expect(match?.name, '张三');
  });

  test('matches common Chinese homophones', () {
    final match = VoiceContactMatcher.findBest(
      '王武',
      [
        const VoiceContactCandidate(name: '王五', phone: '13800000000'),
      ],
    );

    expect(match?.name, '王五');
    expect(
      VoiceContactMatcher.matchesSearch(
        '王武',
        const VoiceContactCandidate(name: '王五', phone: '13800000000'),
      ),
      isTrue,
    );
  });

  test('keeps duplicate names searchable', () {
    const first = VoiceContactCandidate(name: '张三', phone: '13800000000');
    const second = VoiceContactCandidate(name: '张三', phone: '13900000000');

    expect(VoiceContactMatcher.matchesSearch('张三', first), isTrue);
    expect(VoiceContactMatcher.matchesSearch('张三', second), isTrue);
    expect(
      VoiceContactMatcher.matchesSearch('幺三八零零零零零零零零', first),
      isTrue,
    );
  });

  test('does not fuzzy match when two contacts are equally close', () {
    final match = VoiceContactMatcher.findBest(
      '张山',
      [
        const VoiceContactCandidate(name: '张三', phone: '13800000000'),
        const VoiceContactCandidate(name: '张杉', phone: '13900000000'),
      ],
    );

    expect(match, isNull);
  });

  test('queues release while the local voice model is starting', () {
    final session = VoiceSessionGate();

    expect(session.requestStart(), isTrue);
    expect(session.requestStop(), isTrue);
    expect(session.phase, VoiceSessionPhase.starting);
    expect(session.stopRequested, isTrue);

    expect(session.recordingStarted(), isTrue);
    expect(session.phase, VoiceSessionPhase.processing);
  });
}
