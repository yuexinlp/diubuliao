# 丢不了

丢不了是一款本地优先的联系人管理工具，帮助用户把联系人、手机号和备份文件放在自己的设备上管理，减少更换手机或迁移通讯录时的数据丢失。

应用名称：**丢不了**<br>
Flutter 项目名：`contact_atlas`<br>
当前状态：Android 版本可构建和真机测试；项目同时保留 iOS 工程，iOS IPA 需要在 macOS + Xcode 环境中构建。

## 功能

### 数据中心

- 统计联系人总数、分类数量和手机号归属地分布。
- 在中国地图上按手机号归属地展示联系人数量。
- 支持地图缩放、拖动和区域计数。
- 地图展示使用本地号段数据，不申请实时定位权限。

### 联系人

- 新增、编辑、删除联系人。
- 支持姓名、手机号、分类、备注和头像。
- 分类由用户自由填写，例如 `家人 - 张三`、`朋友 - 李四`。
- 支持从手机本地通讯录导入。
- 支持将联系人同步到手机本地通讯录。
- 同名联系人和多个手机号可以同时保留并搜索。

### 导入、导出与备份

- 支持 VCF/vCard 导入和导出。
- 兼容 UTF-8、GBK 等常见中文编码场景。
- 支持分类与姓名格式的解析，例如 `家人~六三`。
- 支持本地备份、恢复和重置。
- 不依赖服务器，联系人数据默认保存在设备本地。

### 语音操作

应用内置 Sherpa-ONNX SenseVoice 模型，语音识别在本地完成，不需要云端 API Key。

支持的示例：

```text
搜索张三
打电话给王五
添加联系人，姓名张三，手机号一三八零零零零零零零零，分类朋友，备注同事
新增联系人姓名张三 手机号13800000000 分类朋友 备注同事
```

语音联系人新增会分别解析姓名、手机号、分类和备注；中文数字手机号会转换为阿拉伯数字，并对 11 位手机号进行校验。联系人搜索支持手机号匹配、同音和有限模糊匹配。

## 隐私与数据安全

- 当前项目没有后端服务和云端数据库。
- 联系人、分类、备注和备份文件不会自动上传到服务器。
- 语音识别模型随应用发布，在本地处理录音。
- 手机号归属地只表示号段对应的大致省市，不代表联系人实时位置；携号转网等情况可能造成归属地不准确。
- 导入、导出、备份和恢复由用户主动操作。

## 技术栈

- Flutter `3.47.5`
- Dart `3.13.4`
- `flutter_contacts`：读取和同步手机本地通讯录
- `file_picker`：选择 VCF 和备份文件
- `record`：录音
- `sherpa_onnx`：本地 SenseVoice 语音识别
- `url_launcher`：拨号跳转
- `gbk_codec`：中文 VCF 编码处理

## 项目结构

```text
contact_atlas/
├── assets/
│   ├── china.json                 # 中国地图区域数据
│   ├── phone.dat                  # 手机号归属地号段数据
│   └── models/                    # 本地 SenseVoice 模型（Git LFS）
├── lib/
│   ├── main.dart                  # 主界面、联系人与数据中心流程
│   ├── local_voice.dart            # 本地语音识别
│   ├── voice_command.dart          # 语音命令解析
│   ├── voice_contact_draft.dart    # 语音新增联系人字段解析
│   ├── voice_matching.dart         # 联系人模糊匹配
│   └── voice_session.dart          # 语音会话状态
├── test/
│   └── widget_test.dart            # 功能和回归测试
├── android/                       # Android 工程
├── ios/                           # iOS 工程
└── pubspec.yaml
```

## 环境要求

- Flutter stable `3.47.5` 或兼容版本
- Dart SDK `3.13.4` 或兼容版本
- Android：Android SDK、Android SDK Platform Tools
- iOS：macOS、Xcode 和 CocoaPods
- Git LFS：用于拉取约 226 MB 的 SenseVoice 模型文件

## 获取和运行

```bash
git clone https://github.com/yuexinlp/diubuliao.git
cd diubuliao

git lfs install
git lfs pull
flutter pub get
flutter run
```

如果没有拉取语音模型，应用的本地语音功能无法正常初始化；其他联系人管理功能仍可用于开发和调试。

## 检查与构建

```bash
flutter analyze
flutter test
flutter build apk --debug
```

Android Debug APK 输出目录：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

iOS 构建需要在 macOS 上执行：

```bash
flutter pub get
cd ios
pod install
cd ..
flutter build ipa
```

生成 IPA 后，可以根据测试用途使用 Apple 开发者签名、爱思助手或其他合规的设备侧载方式安装。蒲公英等平台只负责分发，不能替代 iOS 签名。

## 权限说明

Android 和 iOS 版本可能请求以下权限：

- 通讯录读写：导入联系人和同步到手机通讯录。
- 麦克风：录制语音搜索和语音新增联系人。
- 文件访问：导入、导出 VCF 和本地备份文件。

应用不需要定位权限。地图归属地展示来自本地手机号号段数据。

## 当前限制

- 手机号归属地按号段识别，不是 GPS 定位，也不能保证携号转网后的实际所在地。
- 内置本地语音模型会显著增加安装包体积，Android 包体通常在数百 MB 级别。
- 当前 Android Release 构建仍使用测试签名配置，正式发布前需要替换为自己的签名密钥。
- iOS IPA 无法在 Windows 上构建，必须使用 macOS + Xcode。
- iOS 的通讯录、麦克风和本地语音模型功能需要在真实 iPhone 上单独验证。

## License

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
