# Baby App

Baby App 是一款本地优先的宝宝成长记录应用，同时长期维护两个正式实现。

| 实现 | 目录 | 技术栈 |
| --- | --- | --- |
| React Native | [`apps/react-native`](apps/react-native) | Expo、React Native、TypeScript、pnpm |
| Flutter | [`apps/flutter`](apps/flutter) | Flutter、Dart |

两个版本均可独立构建和测试。产品行为应尽量保持一致；有意差异和待验证能力记录在 [`docs/product-parity.md`](docs/product-parity.md)。

## 开发入口

请按照各自应用目录内的说明安装依赖、运行测试并启动应用：

- [React Native 开发说明](apps/react-native/README.md)
- [Flutter 开发说明](apps/flutter/README.md)

框架专属依赖、缓存和生成文件应保留在对应应用目录内。
