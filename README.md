# org-excalidraw

在 Org mode 中管理 [Excalidraw](https://excalidraw.com) 绘图的 Emacs 包。

## 背景

本项目受 [wdavew/org-excalidraw](https://github.com/wdavew/org-excalidraw) 启发，但由于原库存在以下问题，进行了完全重写：

### 与原库的关系

[wdavew/org-excalidraw](https://github.com/wdavew/org-excalidraw) 是最早将 Excalidraw 集成到 Org mode 的方案，它的核心思路是通过自定义 `excalidraw:` 链接类型实现绘图管理。本项目继承了这一思路，但在实现层面做了根本性的改变。

### 原库存在的问题

1. **内联图片显示失效** — 原库依赖 `org-link-set-parameters` 的 `:image-data-fun` 属性来实现内联图片渲染。但 Org mode 9.7 移除了 `:image-data-fun` 的支持，导致自定义链接类型完全无法内联显示图片，`org-display-inline-images` 执行后报错 "No images to display inline"。

2. **文件监听不完整** — 原库的 `file-notify` 回调仅监听 `renamed` 事件，在 macOS 上保存文件产生的是 `changed` 事件，导致在 Excalidraw 中保存绘图后不会自动重新生成 SVG。

3. **SVG 文件名不一致** — 使用 Excalidraw 应用自带的导出功能时，生成的 SVG 文件名与源文件名不一致，导致链接失效。

4. **缺少批量操作** — 没有提供批量重新导出所有绘图的功能，当需要迁移或修复时只能逐个处理。

### 本库的解决方案

本库完全重写了实现，核心技术变化：

- **内联显示**：通过 `:after` advice 扩展 `org-display-inline-images`，在原函数处理完 `file:` 和 `attachment:` 链接后，额外扫描 `excalidraw:` 链接并创建图片 overlay。这样既兼容 Org 9.7+，又与原生的 `org-remove-inline-images` 完全兼容。
- **链接类型**：仍然使用 `org-link-set-parameters` 注册 `excalidraw:` 链接，但只用于 `:follow`（打开源文件）和 `:export`（HTML/LaTeX 导出），不再依赖已废弃的 `:image-data-fun`。
- **文件监听**：同时响应 `renamed` 和 `changed` 事件，确保在 macOS/Linux 上都能正确触发自动导出。
- **宽度控制**：支持全局默认宽度和 `#+ATTR_ORG: :width` 逐图覆盖，解决了 SVG 内联显示尺寸过小的问题。
- **跨平台**：自动检测操作系统，选择正确的打开命令（macOS `open` / Linux `xdg-open` / Windows `start`）。

## 功能

- 自定义 `excalidraw:` 链接类型：`[[excalidraw:uuid.excalidraw]]`
- Org buffer 中内联显示 SVG 图片（兼容 Org 9.7+）
- `C-c C-o` 打开链接时启动 Excalidraw 编辑源文件
- 保存 `.excalidraw` 文件后自动重新生成 SVG
- HTML / LaTeX 导出支持
- 可配置的图片显示宽度
- 批量导出所有绘图

## 依赖

- Emacs 27.1+
- Org mode 9.3+
- [excalidraw_export](https://github.com/nichochar/excalidraw-export) CLI 工具
- [Excalidraw](https://excalidraw.com) 桌面应用或 PWA

### 安装 excalidraw_export

```bash
npm install -g excalidraw_export
```

### 安装 Excalidraw 字体

为确保 SVG 正确显示，需要安装 Excalidraw 使用的字体。可从 [excalidraw_export 仓库](https://github.com/nichochar/excalidraw-export) 获取。

## 安装

### Doom Emacs

`packages.el`:

```elisp
(package! org-excalidraw
  :recipe (:host github :repo "你的用户名/org-excalidraw"))
```

`config.el`:

```elisp
(use-package! org-excalidraw
  :after org
  :config
  (setq org-excalidraw-directory "~/draws"
        org-excalidraw-image-width 800)
  (org-excalidraw-setup))

(map! :after org
      :map org-mode-map
      "C-c e c" #'org-excalidraw-create-drawing
      "C-c e a" #'org-excalidraw-export-all)
```

### use-package + straight.el

```elisp
(use-package org-excalidraw
  :straight (:type git :host github :repo "你的用户名/org-excalidraw")
  :after org
  :config
  (setq org-excalidraw-directory "~/draws"
        org-excalidraw-image-width 800)
  (org-excalidraw-setup))
```

### 手动安装

将 `org-excalidraw.el` 放入 `load-path`，然后：

```elisp
(require 'org-excalidraw)
(setq org-excalidraw-directory "~/draws")
(with-eval-after-load 'org
  (org-excalidraw-setup))
```

## 使用

### 创建绘图

在 Org buffer 中执行 `M-x org-excalidraw-create-drawing`（或 `C-c e c`）：

1. 在 `org-excalidraw-directory` 下创建新的 `.excalidraw` 文件
2. 立即导出为 SVG
3. 在光标处插入 `[[excalidraw:uuid.excalidraw]]` 链接
4. 用系统应用打开 Excalidraw 进行编辑

### 查看绘图

按 `C-c C-x C-v`（`org-toggle-inline-images`）即可在 buffer 中内联显示 SVG。

### 编辑绘图

在链接上按 `C-c C-o` 打开对应的 `.excalidraw` 源文件。在 Excalidraw 中保存后，SVG 会自动重新生成。

### 批量导出

执行 `M-x org-excalidraw-export-all`（或 `C-c e a`）重新导出目录下所有 `.excalidraw` 文件。

### 控制图片尺寸

全局默认宽度：

```elisp
(setq org-excalidraw-image-width 1000)
```

逐图覆盖：

```org
#+ATTR_ORG: :width 600
[[excalidraw:uuid.excalidraw]]
```

## 自定义变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `org-excalidraw-directory` | `"~/draws"` | `.excalidraw` 文件存储目录 |
| `org-excalidraw-image-width` | `800` | 内联显示和 HTML 导出的默认宽度（像素），`nil` 表示原始尺寸 |
| `org-excalidraw-export-command` | `"excalidraw_export --rename_fonts=true"` | SVG 导出命令 |
| `org-excalidraw-open-command` | 自动检测系统 | 打开 `.excalidraw` 文件的系统命令 |
| `org-excalidraw-file-watch-p` | `t` | 是否监听文件变化并自动导出 |

## 命令

| 命令 | 说明 |
|------|------|
| `org-excalidraw-create-drawing` | 创建新绘图并插入链接 |
| `org-excalidraw-export-all` | 批量导出所有绘图为 SVG |
| `org-excalidraw-setup` | 初始化（注册链接类型 + advice + 文件监听）|
| `org-excalidraw-teardown` | 卸载（移除 advice + 停止文件监听）|

## 许可证

GPL-3.0
