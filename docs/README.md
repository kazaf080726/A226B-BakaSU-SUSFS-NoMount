# 文档索引 / Documentation index

> 🌐 **中文（默认）** | [English](en/README.md)

所有文档都提供中英文两个版本：中文是默认版本，英文镜像在 [`docs/en/`](en/)。
Every document exists in Chinese (default) and English (`docs/en/`).

| 内容 / Topic | 中文（默认） | English |
|---|---|---|
| 项目主页 / Project home | [README.md](../README.md) | [README.en.md](../README.en.md) |
| 功能清单：每项功能落在哪个文件、怎么验证 / Feature inventory: file, line, verification | [FEATURES.md](FEATURES.md) | [en/FEATURES.md](en/FEATURES.md) |
| 构建与可复现性（8 个不确定性来源及修法）/ Build & reproducibility | [BUILD.md](BUILD.md) | [en/BUILD.md](en/BUILD.md) |
| 变更历史 / Changelog | [CHANGELOG.md](CHANGELOG.md) | [en/CHANGELOG.md](en/CHANGELOG.md) |
| v1.4.0 发版说明 / v1.4.0 release notes | [RELEASE-v1.4.0.md](RELEASE-v1.4.0.md) | [en/RELEASE-v1.4.0.md](en/RELEASE-v1.4.0.md) |
| 发布帖草稿 / Announcement post draft | [XDA.md](XDA.md) | [en/XDA.md](en/XDA.md) |
| 接管者笔记：接手第一步与 10 个坑 / Maintainer notes | [MAINTAINER-NOTES.md](MAINTAINER-NOTES.md) | [en/MAINTAINER-NOTES.md](en/MAINTAINER-NOTES.md) |

## 快速开始 / Quick start

1. 下载 / Download: [Releases](https://github.com/kazaf080726/A226B-BakaSU-SUSFS-NoMount/releases)
2. 备份原厂 boot / Back up the stock boot image
3. TWRP 刷入 `A226B-BakaSU-SUSFS-NoMount-*.zip` / flash it in TWRP
4. 安装 BakaSU 管理器 / install the BakaSU manager

细节见 [README.md](../README.md) 第五节与 [README.en.md](../README.en.md) section 5。
Details: section 5 of either README.

## 维护约定 / Maintenance convention

改动文档时**两个语言版本要一起改**，并且数字（哈希、行数、文件名）必须一致——
一个语言里留下过期哈希，比不写哈希更糟。
When editing a document, **update both languages** and keep the numbers (hashes, line counts, file names)
identical — a stale hash in one language is worse than no hash at all.
