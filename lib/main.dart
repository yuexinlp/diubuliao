import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as device_contacts;
import 'package:gbk_codec/gbk_codec.dart' as gbk_codec;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' as services;
import 'package:url_launcher/url_launcher.dart';

import 'local_voice.dart';
import 'voice_matching.dart';
import 'voice_session.dart';
export 'voice_command.dart';
import 'voice_command.dart';

void main() => runApp(const LostProofApp());

class LostProofApp extends StatelessWidget {
  const LostProofApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF172C3D);
    const blue = Color(0xFF246B82);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '丢不了',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.light,
          primary: blue,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F7F5),
          foregroundColor: ink,
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFE6F1F3),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: blue),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(11)),
            borderSide: BorderSide(color: Color(0xFFE2E8E6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(11)),
            borderSide: BorderSide(color: Color(0xFFE2E8E6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(11)),
            borderSide: BorderSide(color: blue),
          ),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final store = ContactStore();
  int page = 0;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final current = switch (page) {
          0 => OverviewPage(store: store),
          1 => ContactsPage(store: store),
          _ => MinePage(store: store),
        };
        return Scaffold(
          body: SafeArea(child: current),
          bottomNavigationBar: NavigationBar(
            selectedIndex: page,
            onDestinationSelected: (value) => setState(() => page = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: '数据中心',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: '联系人',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          ),
        );
      },
    );
  }
}

class ContactItem {
  ContactItem({
    required this.name,
    required this.phone,
    this.company = '',
    this.category = '未分类',
    this.region = '',
    this.id = '',
  });

  String id;
  String name;
  String phone;
  String company;
  String category;
  String region;

  String get normalizedPhone => normalizePhone(phone);
  String get displayRegion => phoneRegion(phone);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'company': company,
    'remark': company,
    'category': category,
    'region': region,
  };

  factory ContactItem.fromJson(Map<String, dynamic> json) => ContactItem(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? '未命名联系人'}',
    phone: '${json['phone'] ?? ''}',
    company: '${json['company'] ?? json['remark'] ?? ''}',
    category: _savedCategory('${json['category'] ?? ''}'),
    region: '',
  );
}

String contactTitle(ContactItem contact) {
  final name = contact.name.trim().isEmpty ? '未命名联系人' : contact.name.trim();
  final category = contact.category.trim();
  return category.isEmpty ? name : '$category - $name';
}

String _savedCategory(String value) =>
    value == '手机通讯录' || value == '未分类' ? '' : value;

class ContactStore extends ChangeNotifier {
  final contacts = <ContactItem>[];
  bool loading = true;
  String lastAction = '准备就绪';
  File? _file;

  Future<void> load() async {
    await PhoneRegionDatabase.load();
    final directory = await getApplicationDocumentsDirectory();
    _file = File('${directory.path}/lost-proof-contacts.json');
    if (await _file!.exists()) {
      try {
        final data = jsonDecode(await _file!.readAsString()) as List<dynamic>;
        contacts
          ..clear()
          ..addAll(
            data.map(
              (item) =>
                  ContactItem.fromJson(Map<String, dynamic>.from(item as Map)),
            ),
          );
        lastAction = '已恢复本地副本';
      } catch (_) {
        contacts.clear();
        lastAction = '本地副本无法读取，已清空';
      }
    } else {
      contacts.clear();
      lastAction = '暂无本地副本';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> save() async {
    _file ??= File(
      '${(await getApplicationDocumentsDirectory()).path}/lost-proof-contacts.json',
    );
    await _file!.writeAsString(
      jsonEncode(contacts.map((item) => item.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<String> readFromPhone() async {
    if (!await device_contacts.FlutterContacts.requestPermission(
      readonly: false,
    )) {
      return '没有获得通讯录权限';
    }
    final phoneContacts = await device_contacts.FlutterContacts.getContacts(
      withProperties: true,
    );
    final imported = <ContactItem>[];
    for (final contact in phoneContacts) {
      for (final phone in contact.phones) {
        final number = phone.number.trim();
        if (number.isEmpty) continue;
        final partsName = <String>[
          contact.name.first,
          contact.name.middle,
          contact.name.last,
        ].where((part) => part.trim().isNotEmpty).join(' ').trim();
        final name = contact.displayName.trim().isNotEmpty
            ? contact.displayName.trim()
            : partsName;
        imported.add(
          ContactItem(
            id: contact.id,
            name: name.isEmpty ? '未命名联系人' : name,
            phone: number,
            company: contact.organizations.isEmpty
                ? ''
                : contact.organizations.first.company,
            category: '',
            region: '',
          ),
        );
      }
    }
    final unique = <String, ContactItem>{};
    for (final item in imported) {
      unique[item.normalizedPhone] ??= item;
    }
    contacts
      ..clear()
      ..addAll(unique.values);
    lastAction = '刚刚读取 ${contacts.length} 位联系人';
    await save();
    return lastAction;
  }

  Future<String> syncToPhone() async {
    if (!await device_contacts.FlutterContacts.requestPermission(
      readonly: false,
    )) {
      return '没有获得通讯录权限';
    }
    final phoneContacts = await device_contacts.FlutterContacts.getContacts(
      withProperties: true,
    );
    final byPhone = <String, device_contacts.Contact>{};
    for (final contact in phoneContacts) {
      for (final phone in contact.phones) {
        byPhone[normalizePhone(phone.number)] ??= contact;
      }
    }
    var updated = 0;
    var added = 0;
    for (final item in contacts) {
      if (item.normalizedPhone.isEmpty) continue;
      final existing = byPhone[item.normalizedPhone];
      if (existing == null) {
        await device_contacts.Contact(
          name: device_contacts.Name(first: contactTitle(item)),
          phones: [device_contacts.Phone(item.phone)],
        ).insert();
        added++;
      } else {
        existing.name = device_contacts.Name(first: contactTitle(item));
        if (item.company.isNotEmpty) {
          existing.organizations = [
            device_contacts.Organization(company: item.company),
          ];
        }
        await existing.update();
        updated++;
      }
    }
    lastAction = '已同步到手机：新增 $added，更新 $updated';
    notifyListeners();
    return lastAction;
  }

  Future<void> upsert(ContactItem item) async {
    item.region = phoneRegion(item.phone);
    final index = contacts.indexWhere(
      (current) => current.id == item.id && item.id.isNotEmpty,
    );
    if (index >= 0) {
      contacts[index] = item;
    } else {
      item.id = DateTime.now().microsecondsSinceEpoch.toString();
      contacts.insert(0, item);
    }
    lastAction = '已保存 ${item.name}';
    await save();
  }

  Future<void> remove(ContactItem item) async {
    contacts.remove(item);
    lastAction = '已删除 ${item.name}';
    await save();
  }

  Future<void> resetData() async {
    contacts.clear();
    lastAction = '已重置本地数据';
    await save();
  }

  Future<String> importVcf() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['vcf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return '已取消导入';
    final file = picked.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) return '无法读取 VCF 文件';
    final parsed = VCardCodec.parseBytes(bytes);
    if (parsed.isEmpty) return 'VCF 中没有识别到联系人';
    contacts
      ..clear()
      ..addAll(parsed);
    lastAction = '已导入 ${parsed.length} 位联系人';
    await save();
    return lastAction;
  }

  Future<String> exportVcf() async {
    final bytes = Uint8List.fromList(
      utf8.encode(VCardCodec.serialize(contacts)),
    );
    final path = await FilePicker.platform.saveFile(
      fileName: '丢不了-联系人备份.vcf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['vcf'],
    );
    if (path == null) return '已取消导出';
    lastAction = '已导出 ${contacts.length} 位联系人';
    notifyListeners();
    return lastAction;
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({required this.store, super.key});
  final ContactStore store;

  @override
  Widget build(BuildContext context) {
    final regions = <String, int>{};
    for (final contact in store.contacts) {
      regions[contact.displayRegion] =
          (regions[contact.displayRegion] ?? 0) + 1;
    }
    final top = regions.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: PageHeader(
              eyebrow: 'MY DATA',
              title: '数据中心',
              subtitle: '自己的联系人，自己做主。',
              action: IconButton(
                onPressed: () => showMessage(context, store.lastAction),
                icon: const Icon(Icons.info_outline),
                tooltip: '状态',
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
          sliver: SliverToBoxAdapter(
            child: MapCard(regions: top, contacts: store.contacts),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '数据概况',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => showMessage(context, store.lastAction),
                  child: const Text('刷新状态'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.8,
            children: [
              StatTile(
                value: '${store.contacts.length}',
                label: '已保存联系人',
                icon: Icons.people_outline,
              ),
              StatTile(
                value: '${regions.length}',
                label: '覆盖省市',
                icon: Icons.public,
              ),
              StatTile(
                value: '${duplicateCount(store.contacts)}',
                label: '重复手机号',
                icon: Icons.merge_type,
              ),
              StatTile(
                value: store.loading ? '读取中' : '正常',
                label: '本地副本',
                icon: Icons.verified_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ContactsPage extends StatefulWidget {
  const ContactsPage({required this.store, super.key});
  final ContactStore store;

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  final search = TextEditingController();
  final searchFocus = FocusNode();
  final localVoice = LocalVoiceRecognizer();
  final voiceSession = VoiceSessionGate();
  String voiceFeedback = '';

  bool get listening => voiceSession.phase == VoiceSessionPhase.listening;
  bool get voiceProcessing =>
      voiceSession.phase == VoiceSessionPhase.processing;

  @override
  void dispose() {
    localVoice.dispose();
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> toggleVoiceSearch() async {
    if (listening) {
      await stopVoiceSearch();
    } else if (voiceSession.phase == VoiceSessionPhase.idle) {
      await startVoiceSearch();
    }
  }

  Future<void> startVoiceSearch() async {
    if (!voiceSession.requestStart()) return;
    if (mounted) {
      setState(() {
        voiceFeedback = '正在准备本地语音模型...';
      });
    }
    try {
      search.clear();
      await localVoice.start(
        onStatus: (message) {
          if (mounted) setState(() => voiceFeedback = message);
        },
      );
      final stopImmediately = voiceSession.recordingStarted();
      if (stopImmediately) {
        if (mounted) {
          setState(() => voiceFeedback = '正在处理识别结果...');
        }
        await _finishVoiceRecognition();
        return;
      }
      if (mounted) {
        setState(() {
          voiceFeedback = '正在聆听，请说话...';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          voiceFeedback = '本地语音启动失败：$error';
        });
        showMessage(context, '本地语音启动失败：$error');
      }
      voiceSession.recordingStartFailed();
    }
  }

  Future<void> stopVoiceSearch() async {
    if (!voiceSession.requestStop()) return;
    if (mounted) {
      setState(() {
        voiceFeedback = '正在处理识别结果...';
      });
    }
    await _finishVoiceRecognition();
  }

  Future<void> _finishVoiceRecognition() async {
    try {
      final text = await localVoice.stopAndRecognize(
        onStatus: (message) {
          if (mounted) setState(() => voiceFeedback = message);
        },
      );
      voiceSession.processingFinished();
      if (!mounted) return;
      setState(() {
        voiceFeedback = text.isEmpty ? '没有识别到内容，请再说一次' : '已识别：$text';
      });
      if (text.isEmpty) {
        showMessage(context, '没有识别到内容，请再说一次');
      } else {
        await _applyVoiceCommand(text);
      }
    } catch (error) {
      if (!mounted) return;
      voiceSession.processingFinished();
      setState(() {
        voiceFeedback = '停止录音失败：$error';
      });
      showMessage(context, '停止录音失败：$error');
    }
  }

  Future<void> _applyVoiceCommand(String text) async {
    final command = VoiceCommandParser.parse(text);
    switch (command.type) {
      case VoiceCommandType.call:
        final matched = _matchVoiceContact(command.value);
        if (matched == null) {
          setState(
            () => voiceFeedback =
                '已识别：$text，未找到明确联系人“${command.value}”',
          );
        } else {
          setState(
            () => voiceFeedback = '已找到：${matched.name}，正在拨号...',
          );
          await callPhone(context, matched.phone);
        }
        return;
      case VoiceCommandType.search:
        final displayQuery = _voiceSearchDisplayQuery(command.value);
        if (displayQuery != null) {
          search.text = displayQuery;
          setState(() {});
        } else {
          setState(() => voiceFeedback = '已识别：$text，未找到匹配联系人');
        }
        return;
      case VoiceCommandType.create:
        final draft = command.contactDraft;
        if (draft != null && !draft.hasValidMobile && mounted) {
          setState(
            () => voiceFeedback = '已识别姓名，请补充完整的11位手机号后保存',
          );
        }
        final result = await showDialog<ContactItem>(
          context: context,
          builder: (_) => ContactEditor(
            initialName: draft?.name ?? command.value,
            initialPhone: draft?.phoneDigits ?? '',
            initialCompany: draft?.remark ?? '',
            initialCategory: draft?.category ?? '',
            strictPhone: draft != null,
          ),
        );
        if (result != null && mounted) {
          await widget.store.upsert(result);
          if (mounted) showMessage(context, '已保存 ${result.name}');
        }
        return;
      case VoiceCommandType.unknown:
        setState(() => voiceFeedback = '已识别：$text');
    }
  }

  ContactItem? _matchVoiceContact(String value) {
    final match = VoiceContactMatcher.findBest(
      value,
      widget.store.contacts.map(_voiceCandidate),
    );
    if (match == null) return null;
    return widget.store.contacts.firstWhere(
      (contact) =>
          contact.name == match.name && contact.phone == match.phone,
    );
  }

  String? _voiceSearchDisplayQuery(String value) =>
      VoiceContactMatcher.displaySearchQuery(
        value,
        widget.store.contacts.map(_voiceCandidate),
      );

  VoiceContactCandidate _voiceCandidate(ContactItem contact) =>
      VoiceContactCandidate(
        name: contact.name,
        phone: contact.phone,
        searchText:
            '${contact.category}${contact.name}${contact.company}${contact.phone}${contact.displayRegion}',
      );

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final visible = widget.store.contacts.where((contact) {
      return query.isEmpty ||
          VoiceContactMatcher.matchesSearch(query, _voiceCandidate(contact));
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          child: PageHeader(
            eyebrow: 'CONTACTS',
            title: '联系人',
            subtitle: '${widget.store.contacts.length} 位 · 手机号重复以 App 名称为准',
            action: IconButton.filledTonal(
              onPressed: () => editContact(context),
              icon: const Icon(Icons.add),
              tooltip: '添加联系人',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  focusNode: searchFocus,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '搜索姓名、公司或号码',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              GestureDetector(
                onTap: toggleVoiceSearch,
                onLongPressStart: (_) => startVoiceSearch(),
                onLongPressEnd: (_) => stopVoiceSearch(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: listening || voiceProcessing
                        ? const Color(0xFFFFF0E5)
                        : const Color(0xFFE6F1F3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    listening ? Icons.mic : Icons.mic_none,
                    color: listening
                        ? const Color(0xFFB55A25)
                        : const Color(0xFF246B82),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (voiceFeedback.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                voiceFeedback,
                style: TextStyle(
                  fontSize: 12,
                  color: listening
                      ? const Color(0xFFB55A25)
                      : const Color(0xFF71808B),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${visible.length} 位联系人',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final message = await widget.store.syncToPhone();
                  if (context.mounted) showMessage(context, message);
                },
                icon: const Icon(Icons.sync, size: 17),
                label: const Text('同步到手机'),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                sliver: SliverList.builder(
                  itemCount: visible.isEmpty ? 1 : visible.length,
                  itemBuilder: (context, index) {
                    if (visible.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 28),
                        child: Center(
                          child: Text(
                            '暂无联系人',
                            style: TextStyle(color: Color(0xFF71808B)),
                          ),
                        ),
                      );
                    }
                    final contact = visible[index];
                    return ContactRow(
                      contact: contact,
                      onCall: () => callPhone(context, contact.phone),
                      onEdit: () => editContact(context, contact),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> editContact(BuildContext context, [ContactItem? contact]) async {
    final result = await showDialog<ContactItem>(
      context: context,
      builder: (_) => ContactEditor(contact: contact),
    );
    if (result == null || !mounted) return;
    await widget.store.upsert(result);
    if (!mounted) return;
    showMessage(this.context, '已保存 ${result.name}');
  }
}

class MinePage extends StatelessWidget {
  const MinePage({required this.store, super.key});
  final ContactStore store;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: PageHeader(
              eyebrow: 'PERSONAL SPACE',
              title: '我的',
              subtitle: '备份、恢复和同步，都在这里。',
              action: const SizedBox.shrink(),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F1F3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF246B82)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '本地副本正常',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${store.contacts.length} 位联系人 · ${store.lastAction}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF71808B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Color(0xFF3A9B70),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 25, 20, 0),
          sliver: const SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '数据操作',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  'VCF 3.0',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                VaultAction(
                  icon: Icons.phone_android,
                  title: '读取手机通讯录',
                  subtitle: '将手机联系人保存到 App',
                  onTap: () async {
                    final result = await store.readFromPhone();
                    if (context.mounted) showMessage(context, result);
                  },
                ),
                VaultAction(
                  icon: Icons.sync,
                  title: '同步到手机本地通讯录',
                  subtitle: '手机号匹配，App 名称覆盖手机名称',
                  onTap: () async {
                    final result = await store.syncToPhone();
                    if (context.mounted) showMessage(context, result);
                  },
                ),
                VaultAction(
                  icon: Icons.file_upload_outlined,
                  title: '从 VCF 导入',
                  subtitle: '恢复之前保存的联系人',
                  onTap: () async {
                    final result = await store.importVcf();
                    if (context.mounted) showMessage(context, result);
                  },
                ),
                VaultAction(
                  icon: Icons.file_download_outlined,
                  title: '导出 VCF 备份',
                  subtitle: '保存到手机文件、电脑或网盘',
                  onTap: () async {
                    final result = await store.exportVcf();
                    if (context.mounted) showMessage(context, result);
                  },
                ),
                VaultAction(
                  icon: Icons.restore_rounded,
                  title: '恢复本地副本',
                  subtitle: '重新读取 App 私有目录中的数据',
                  onTap: () async {
                    await store.load();
                    if (context.mounted) showMessage(context, '已恢复本地副本');
                  },
                ),
                VaultAction(
                  icon: Icons.delete_sweep_outlined,
                  title: '重置本地数据',
                  subtitle: '清空 App 内联系人，不影响手机通讯录',
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('重置本地数据'),
                        content: const Text('将清空 App 内全部联系人，但不会删除手机通讯录。确定继续吗？'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('确认重置'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await store.resetData();
                      if (context.mounted) showMessage(context, '本地数据已重置');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
          sliver: const SliverToBoxAdapter(
            child: Text(
              '使用说明',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: const SliverToBoxAdapter(
            child: Text(
              'App 内联系人是主数据。更换手机前请导出 VCF 并保存到电脑、网盘或微信文件传输助手。同步到手机前会按手机号匹配，重复号码以 App 内名称为准。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Color(0xFF5F707A),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.action,
    super.key,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                fontSize: 10,
                letterSpacing: 1.4,
                color: Color(0xFFB55A25),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                height: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF71808B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
      action,
    ],
  );
}

class SyncBarDelegate extends SliverPersistentHeaderDelegate {
  const SyncBarDelegate({required this.count, required this.onSync});
  final int count;
  final VoidCallback onSync;

  @override
  double get minExtent => 62;

  @override
  double get maxExtent => 62;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: const Color(0xFFF6F7F5),
    elevation: overlapsContent ? 2 : 0,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$count 位联系人',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          TextButton.icon(
            onPressed: onSync,
            icon: const Icon(Icons.sync, size: 17),
            label: const Text('同步到手机'),
          ),
        ],
      ),
    ),
  );

  @override
  bool shouldRebuild(covariant SyncBarDelegate oldDelegate) =>
      oldDelegate.count != count || oldDelegate.onSync != onSync;
}

class ContactRow extends StatelessWidget {
  const ContactRow({
    required this.contact,
    required this.onCall,
    required this.onEdit,
    super.key,
  });
  final ContactItem contact;
  final VoidCallback onCall;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFE4E8E7)),
    ),
    child: ListTile(
      onTap: onEdit,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      minVerticalPadding: 4,
      leading: SizedBox(
        width: 44,
        height: 56,
        child: Center(
          child: CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFFFF0E5),
            child: Text(
              contact.name.isEmpty ? '?' : contact.name.characters.first,
              style: const TextStyle(
                color: Color(0xFFB55A25),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
      title: Text(
        contactTitle(contact),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${contact.displayRegion}\n${contact.phone}${contact.company.isEmpty ? '' : ' · ${contact.company}'}',
        style: const TextStyle(
          fontSize: 11,
          height: 1.5,
          color: Color(0xFF71808B),
        ),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 56,
            child: Center(
              child: IconButton.filledTonal(
                onPressed: onCall,
                icon: const Icon(Icons.phone, size: 17),
                tooltip: '拨打',
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 56,
            child: Center(
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') confirmDelete(context, contact);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class ContactEditor extends StatefulWidget {
  const ContactEditor({
    this.contact,
    this.initialName,
    this.initialPhone,
    this.initialCompany,
    this.initialCategory,
    this.strictPhone = false,
    super.key,
  });
  final ContactItem? contact;
  final String? initialName;
  final String? initialPhone;
  final String? initialCompany;
  final String? initialCategory;
  final bool strictPhone;

  @override
  State<ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<ContactEditor> {
  late final name = TextEditingController(
    text: widget.contact?.name ?? widget.initialName ?? '',
  );
  late final phone = TextEditingController(
    text: widget.contact?.phone ?? widget.initialPhone ?? '',
  );
  late final company = TextEditingController(
    text: widget.contact?.company ?? widget.initialCompany ?? '',
  );
  late final category = TextEditingController(
    text: widget.contact?.category ?? widget.initialCategory ?? '',
  );
  String? phoneError;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    company.dispose();
    category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.contact == null ? '添加联系人' : '编辑联系人'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '姓名'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            onChanged: (_) {
              if (phoneError != null) setState(() => phoneError = null);
            },
            decoration: InputDecoration(
              labelText: widget.strictPhone ? '手机号（11位）' : '手机号',
              errorText: phoneError,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: company,
            decoration: const InputDecoration(labelText: '备注'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: category,
            decoration: const InputDecoration(
              labelText: '分类（可选）',
              hintText: '例如：家人',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
          final normalizedPhone = widget.strictPhone
              ? mainlandMobileDigits(phone.text)
              : null;
          if (widget.strictPhone && normalizedPhone == null) {
            setState(() => phoneError = '请输入完整的11位手机号');
            return;
          }
          final old = widget.contact;
          Navigator.pop(
            context,
            ContactItem(
              id: old?.id ?? '',
              name: name.text.trim(),
              phone: normalizedPhone ?? phone.text.trim(),
              company: company.text.trim(),
              category: category.text.trim(),
              region: phoneRegion(phone.text),
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}

class VaultAction extends StatelessWidget {
  const VaultAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: ListTile(
      onTap: onTap,
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E8E7)),
      ),
      leading: Icon(icon, color: const Color(0xFF246B82)),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: Color(0xFF71808B)),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: Color(0xFF8DA0A6),
      ),
    ),
  );
}

class StatTile extends StatelessWidget {
  const StatTile({
    required this.value,
    required this.label,
    required this.icon,
    super.key,
  });
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE4E8E7)),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF246B82), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF71808B)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MapCard extends StatefulWidget {
  const MapCard({required this.regions, required this.contacts, super.key});
  final List<MapEntry<String, int>> regions;
  final List<ContactItem> contacts;

  @override
  State<MapCard> createState() => _MapCardState();
}

class _MapCardState extends State<MapCard> {
  final transformation = TransformationController();
  final mapFuture = ChinaMapData.load();
  Size viewportSize = Size.zero;

  void zoomBy(double factor) {
    final current = transformation.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(1.0, 4.0).toDouble();
    if (target == current || viewportSize == Size.zero) return;
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final ratio = target / current;
    final aroundCenter = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    transformation.value = aroundCenter.multiplied(transformation.value);
  }

  void resetZoom() {
    transformation.value = Matrix4.identity();
  }

  @override
  void dispose() {
    transformation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 238,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1ED),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDCE8E3)),
    ),
    child: FutureBuilder<ChinaMapData>(
      future: mapFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        final data = snapshot.data!;
        final active = widget.regions
            .where((entry) => entry.key != '归属地待识别')
            .toList();
        return LayoutBuilder(
          builder: (context, constraints) {
            viewportSize = constraints.biggest;
            return Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    transformationController: transformation,
                    minScale: 1,
                    maxScale: 4,
                    boundaryMargin: const EdgeInsets.all(100),
                    child: AnimatedBuilder(
                      animation: transformation,
                      builder: (context, _) {
                        final scale = transformation.value.getMaxScaleOnAxis();
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: ChinaMapPainter(
                                  data: data,
                                  active: active
                                      .map((e) => provinceKey(e.key))
                                      .toSet(),
                                ),
                              ),
                            ),
                            ...active.map((entry) {
                              final province = data.find(
                                provinceKey(entry.key),
                              );
                              if (province == null) {
                                return const SizedBox.shrink();
                              }
                              final names = widget.contacts
                                  .where(
                                    (contact) =>
                                        provinceKey(contact.displayRegion) ==
                                        provinceKey(entry.key),
                                  )
                                  .map((contact) => contactTitle(contact))
                                  .where((name) => name.trim().isNotEmpty)
                                  .toList();
                              return MapMarker(
                                left: data
                                        .project(province.center, viewportSize)
                                        .dx /
                                    viewportSize.width,
                                top: data
                                        .project(province.center, viewportSize)
                                        .dy /
                                    viewportSize.height,
                                label: '${entry.key} · ${entry.value}',
                                markerScale: 1 / scale,
                                active: entry == active.first,
                                onTap: () =>
                                    showNames(context, entry.key, names),
                              );
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const Positioned(left: 16, top: 12, child: MapLegend()),
                Positioned(
                  right: 6,
                  bottom: 8,
                  child: Column(
                    children: [
                      MapZoomButton(
                        icon: Icons.add,
                        tooltip: '放大地图',
                        onPressed: () => zoomBy(1.35),
                      ),
                      const SizedBox(height: 3),
                      MapZoomButton(
                        icon: Icons.remove,
                        tooltip: '缩小地图',
                        onPressed: () => zoomBy(1 / 1.35),
                      ),
                      const SizedBox(height: 3),
                      MapZoomButton(
                        icon: Icons.center_focus_strong,
                        tooltip: '恢复地图大小',
                        onPressed: resetZoom,
                      ),
                    ],
                  ),
                ),
                const Positioned(
                  left: 14,
                  right: 14,
                  bottom: 10,
                  child: Text(
                    '中国省级归属地 · 可缩放拖动 · 点击标记查看姓名',
                    style: TextStyle(fontSize: 10, color: Color(0xFF60756D)),
                  ),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}

class MapLegend extends StatelessWidget {
  const MapLegend({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.public, size: 15, color: Color(0xFF246B82)),
          SizedBox(width: 6),
          Text(
            '按手机号归属地标绘',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

class MapZoomButton extends StatelessWidget {
  const MapZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      style: IconButton.styleFrom(
        minimumSize: const Size(28, 28),
        maximumSize: const Size(28, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white.withValues(alpha: .88),
        foregroundColor: const Color(0xFF246B82),
      ),
    ),
  );
}

class MapMarker extends StatelessWidget {
  const MapMarker({
    required this.left,
    required this.top,
    required this.label,
    this.onTap,
    this.active = false,
    this.markerScale = 1,
    super.key,
  });
  final double left;
  final double top;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final double markerScale;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: Align(
      alignment: Alignment(left * 2 - 1, top * 2 - 1),
      child: Transform.scale(
        scale: markerScale,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF246B82)
                      : const Color(0xFFF3A26D),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33515D58),
                      blurRadius: 7,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.location_on,
                  size: 15,
                  color: active ? Colors.white : const Color(0xFF8E4423),
                ),
              ),
              const SizedBox(height: 5),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ChinaProvince {
  ChinaProvince({
    required this.name,
    required this.center,
    required this.rings,
  });
  final String name;
  final Offset center;
  final List<List<Offset>> rings;
}

class ChinaMapData {
  ChinaMapData(this.provinces) {
    final points = [
      for (final province in provinces)
        for (final ring in province.rings)
          ...ring,
    ];
    if (points.isEmpty) {
      _minLongitude = 73.5;
      _maxLongitude = 135.0;
      _minLatitude = 18.0;
      _maxLatitude = 54.5;
      return;
    }
    _minLongitude = points
        .map((point) => point.dx)
        .reduce((a, b) => a < b ? a : b);
    _maxLongitude = points
        .map((point) => point.dx)
        .reduce((a, b) => a > b ? a : b);
    _minLatitude = points
        .map((point) => point.dy)
        .reduce((a, b) => a < b ? a : b);
    _maxLatitude = points
        .map((point) => point.dy)
        .reduce((a, b) => a > b ? a : b);
  }

  final List<ChinaProvince> provinces;
  late final double _minLongitude;
  late final double _maxLongitude;
  late final double _minLatitude;
  late final double _maxLatitude;

  static Future<ChinaMapData> load() async {
    final raw = jsonDecode(
      await services.rootBundle.loadString('assets/china.json'),
    ) as Map<String, dynamic>;
    final result = <ChinaProvince>[];
    for (final feature in (raw['features'] as List<dynamic>)) {
      final item = Map<String, dynamic>.from(feature as Map);
      final props = Map<String, dynamic>.from(item['properties'] as Map);
      final geometry = Map<String, dynamic>.from(item['geometry'] as Map);
      final rings = <List<Offset>>[];
      void addPolygon(dynamic polygon) {
        for (final ring in polygon as List<dynamic>) {
          rings.add(
            (ring as List<dynamic>).map((point) {
              final pair = point as List<dynamic>;
              return Offset(
                (pair[0] as num).toDouble(),
                (pair[1] as num).toDouble(),
              );
            }).toList(),
          );
        }
      }

      if (geometry['type'] == 'Polygon') {
        addPolygon(geometry['coordinates']);
      } else {
        for (final polygon in geometry['coordinates'] as List<dynamic>) {
          addPolygon(polygon);
        }
      }
      final cp = props['cp'] as List<dynamic>;
      result.add(
        ChinaProvince(
          name: '${props['name'] ?? ''}',
          center: Offset((cp[0] as num).toDouble(), (cp[1] as num).toDouble()),
          rings: rings,
        ),
      );
    }
    return ChinaMapData(result);
  }

  ChinaProvince? find(String key) {
    for (final province in provinces) {
      if (provinceKey(province.name) == key) return province;
    }
    return null;
  }

  double x(double longitude) {
    final span = _maxLongitude - _minLongitude;
    if (span <= 0) return .5;
    return (.025 + (longitude - _minLongitude) / span * .95).clamp(.025, .975);
  }

  double y(double latitude) {
    final span = _maxLatitude - _minLatitude;
    if (span <= 0) return .5;
    return (.025 + (_maxLatitude - latitude) / span * .95).clamp(.025, .975);
  }

  Offset project(Offset coordinate, Size size) {
    const padding = 8.0;
    final availableWidth =
        (size.width - padding * 2).clamp(1.0, double.infinity).toDouble();
    final availableHeight =
        (size.height - padding * 2).clamp(1.0, double.infinity).toDouble();
    final longitudeSpan = (_maxLongitude - _minLongitude).abs();
    final latitudeSpan = (_maxLatitude - _minLatitude).abs();
    final horizontalScale = availableWidth / longitudeSpan;
    final verticalScale = availableHeight / latitudeSpan;
    final scale = horizontalScale < verticalScale
        ? horizontalScale
        : verticalScale;
    final mapWidth = longitudeSpan * scale;
    final mapHeight = latitudeSpan * scale;
    final left = (size.width - mapWidth) / 2;
    final top = (size.height - mapHeight) / 2;
    return Offset(
      left + (coordinate.dx - _minLongitude) * scale,
      top + (_maxLatitude - coordinate.dy) * scale,
    );
  }
}

class ChinaMapPainter extends CustomPainter {
  ChinaMapPainter({required this.data, required this.active});
  final ChinaMapData data;
  final Set<String> active;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFFD8E6DE);
    final activeFill = Paint()..color = const Color(0xFFB8D8D0);
    final border = Paint()
      ..color = const Color(0xFF9FBEB4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .75;
    for (final province in data.provinces) {
      final paint = active.contains(provinceKey(province.name))
          ? activeFill
          : fill;
      for (final ring in province.rings) {
        if (ring.length < 3) continue;
        final path = Path();
        for (var i = 0; i < ring.length; i++) {
          final point = ring[i];
          final projected = data.project(point, size);
          if (i == 0) {
            path.moveTo(projected.dx, projected.dy);
          } else {
            path.lineTo(projected.dx, projected.dy);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        canvas.drawPath(path, border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ChinaMapPainter oldDelegate) =>
      oldDelegate.active != active;
}

class VCardCodec {
  static String serialize(List<ContactItem> contacts) => contacts
      .map(
        (contact) =>
            'BEGIN:VCARD\nVERSION:3.0\nFN:${escape(contact.name)}\nORG:${escape(contact.company)}\nCATEGORIES:${escape(contact.category)}\nTEL;TYPE=CELL:${escape(contact.phone)}\nEND:VCARD\n',
      )
      .join();

  static List<ContactItem> parseBytes(Uint8List bytes) {
    return parse(_decodeVCard(bytes));
  }

  static List<ContactItem> parse(String text) {
    final cards = _unfold(text)
        .split(RegExp('END:VCARD', caseSensitive: false));
    final result = <ContactItem>[];
    for (final card in cards) {
      if (!card.toUpperCase().contains('BEGIN:VCARD')) continue;
      String name = '未命名联系人', phone = '', company = '', category = '';
      String? fallbackName;
      for (final line in card.split(RegExp(r'\r?\n'))) {
        final index = line.indexOf(':');
        if (index < 0) continue;
        final property = line.substring(0, index);
        final key = property.split(';').first.toUpperCase();
        final value = _decodePropertyValue(
          property,
          line.substring(index + 1).trim(),
        );
        if (key == 'FN' && value.trim().isNotEmpty) name = value.trim();
        if (key == 'N' && value.trim().isNotEmpty) {
          fallbackName = _nameFromN(value);
        }
        if (key == 'TEL' && phone.isEmpty) phone = value.trim();
        if (key == 'ORG' && company.isEmpty) company = value.trim();
        if (key == 'NOTE' && company.isEmpty) company = value.trim();
        if (key == 'CATEGORIES' && category.isEmpty) category = value.trim();
      }
      if (name == '未命名联系人' && fallbackName != null) name = fallbackName;
      if (phone.trim().isNotEmpty) {
        final splitName = _splitCategoryName(name);
        final parsedCategory = category.trim().isEmpty
            ? splitName.category
            : category.trim();
        result.add(
          ContactItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: splitName.name,
            phone: phone,
            company: company,
            category: parsedCategory,
            region: phoneRegion(phone),
          ),
        );
      }
    }
    return result;
  }

  static ({String category, String name}) _splitCategoryName(String value) {
    final match = RegExp(r'^\s*([^~～]+?)\s*[~～]\s*(.+?)\s*$').firstMatch(value);
    if (match == null) {
      return (category: '', name: value.trim());
    }
    return (category: match.group(1)!.trim(), name: match.group(2)!.trim());
  }

  static String escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');
  static String unescape(String value) => value
      .replaceAll('\\n', '\n')
      .replaceAll('\\N', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  static String _unfold(String text) => text
      .replaceAllMapped(RegExp(r'=\r?\n'), (_) => '')
      .replaceAllMapped(RegExp(r'\r?\n[ \t]'), (_) => '');

  static String _nameFromN(String value) {
    final fields = value
        .split(';')
        .map(unescape)
        .where((part) => part.trim().isNotEmpty);
    return fields.join(' ').trim();
  }

  static String _decodePropertyValue(String property, String rawValue) {
    final upper = property.toUpperCase();
    final quotedPrintable = upper.contains('ENCODING=QUOTED-PRINTABLE');
    final charsetMatch = RegExp(
      r'CHARSET\s*=\s*([^;:]+)',
      caseSensitive: false,
    ).firstMatch(property);
    final charset = charsetMatch?.group(1)?.trim().toUpperCase();
    if (quotedPrintable) {
      return _decodeBytes(_decodeQuotedPrintable(rawValue), charset);
    }
    return unescape(rawValue);
  }

  static List<int> _decodeQuotedPrintable(String value) {
    final result = <int>[];
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char == '=' && i + 2 < value.length) {
        final hex = int.tryParse(value.substring(i + 1, i + 3), radix: 16);
        if (hex != null) {
          result.add(hex);
          i += 2;
          continue;
        }
      }
      result.add(char.codeUnitAt(0));
    }
    return result;
  }
}

String _decodeVCard(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  final header = latin1
      .decode(bytes.take(4096).toList(), allowInvalid: true)
      .toUpperCase();
  final charsetMatch = RegExp(r'CHARSET\s*=\s*([^;:\r\n]+)').firstMatch(header);
  final charset = charsetMatch?.group(1)?.trim();
  return _decodeBytes(bytes, charset);
}

String _decodeBytes(List<int> bytes, [String? charset]) {
  final normalized = charset
      ?.toUpperCase()
      .replaceAll('-', '')
      .replaceAll('_', '');
  if (normalized == 'GBK' ||
      normalized == 'GB2312' ||
      normalized == 'GB18030' ||
      normalized == 'CP936') {
    return gbk_codec.gbk_bytes.decode(bytes);
  }
  final utfText = utf8.decode(bytes, allowMalformed: true);
  if (!utfText.contains('\uFFFD')) return utfText;
  return gbk_codec.gbk_bytes.decode(bytes);
}

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

String normalizePhone(String value) {
  var digits = value.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+86')) digits = '0${digits.substring(3)}';
  if (digits.startsWith('0086')) digits = '0${digits.substring(4)}';
  return digits;
}

String provinceKey(String value) => value
    .replaceAll('特别行政区', '')
    .replaceAll('维吾尔自治区', '')
    .replaceAll('壮族自治区', '')
    .replaceAll('回族自治区', '')
    .replaceAll('自治区', '')
    .replaceAll('省', '')
    .replaceAll('市', '')
    .replaceAll('地区', '')
    .trim();

class PhoneRegionDatabase {
  static Uint8List? _data;

  static Future<void> load() async {
    if (_data != null) return;
    final bytes = await services.rootBundle.load('assets/phone.dat');
    _data = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  static String? lookup(String value) {
    final data = _data;
    if (data == null) return null;
    final digits = normalizePhone(value).replaceFirst(RegExp(r'^0'), '');
    if (digits.length < 7) return null;
    final target = int.tryParse(digits.substring(0, 7));
    if (target == null) return null;
    final firstOffset = _int32(data, 4);
    var left = 0;
    var right = (data.length - firstOffset) ~/ 9 - 1;
    while (left <= right) {
      final middle = (left + right) ~/ 2;
      final offset = firstOffset + middle * 9;
      final current = _int32(data, offset);
      if (current == target) {
        final recordOffset = _int32(data, offset + 4);
        var end = recordOffset;
        while (end < data.length && data[end] != 0) {
          end++;
        }
        final fields = utf8
            .decode(data.sublist(recordOffset, end), allowMalformed: true)
            .split('|');
        if (fields.isNotEmpty && fields.first.trim().isNotEmpty) {
          return fields.first.trim();
        }
        return null;
      }
      if (current < target) {
        left = middle + 1;
      } else {
        right = middle - 1;
      }
    }
    return null;
  }

  static int _int32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

String phoneRegion(String value) {
  return PhoneRegionDatabase.lookup(value) ?? '归属地待识别';
}

void showNames(BuildContext context, String province, List<String> names) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .65,
      minChildSize: .35,
      maxChildSize: .9,
      builder: (context, controller) => SafeArea(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              province,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${names.length} 位联系人',
              style: const TextStyle(color: Color(0xFF71808B)),
            ),
            const SizedBox(height: 14),
            if (names.isEmpty)
              const Text('暂无可显示的联系人姓名')
            else
              ...names.map(
                (name) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.person_outline,
                    color: Color(0xFF246B82),
                  ),
                  title: Text(name),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

int duplicateCount(List<ContactItem> contacts) {
  final counts = <String, int>{};
  for (final item in contacts) {
    if (item.normalizedPhone.isNotEmpty) {
      counts[item.normalizedPhone] = (counts[item.normalizedPhone] ?? 0) + 1;
    }
  }
  return counts.values.where((count) => count > 1).length;
}

Future<void> callPhone(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (!await launchUrl(uri) && context.mounted) {
    showMessage(context, '无法打开系统拨号器');
  }
}

Future<void> confirmDelete(BuildContext context, ContactItem contact) async {
  final shell = context.findAncestorStateOfType<_HomeShellState>();
  if (shell == null) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('删除联系人'),
      content: Text('确定删除“${contact.name}”吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (yes == true) {
    await shell.store.remove(contact);
    if (context.mounted) showMessage(context, '已删除 ${contact.name}');
  }
}

void showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
