## 电报广告管理机器人（OCR + 关键词/正则）

功能：
- 识别文本消息与图片（OCR）的文字
- 支持关键词与正则匹配
- 命中后可删除、通知或删除并通知
- 管理命令可动态维护规则

### 截图
- 触发通知截图（占位）：`docs/images/notify-example.png`
- OCR 命中截图（占位）：`docs/images/ocr-hit-example.png`

### 文档
- 详细使用说明见 `docs/USAGE.zh-CN.md`
- 搭建教程见 `docs/SETUP.zh-CN.md`

### 环境准备
1) 安装 Tesseract OCR（含中文）：
```bash
bash scripts/install_tesseract_ocr.sh
```
如果脚本不适用你的系统，请手动安装（Debian/Ubuntu）：
```bash
sudo apt-get update -y && sudo apt-get install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra
```

2) 安装 Python 依赖：
```bash
pip install -r requirements.txt
```

3) 配置环境变量：
- 复制并修改 `.env.example` 为 `.env`，填入 `TELEGRAM_BOT_TOKEN` 和管理员 ID：
```
cp .env.example .env
```

### 运行
```bash
python -m app.bot
```

把机器人拉进群并给予管理员权限（删除消息），用以下命令维护规则：
- `/add_keyword 词语`
- `/remove_keyword 词语`
- `/list_keywords`
- `/add_regex 正则`
- `/remove_regex 正则`
- `/list_regex`
- `/set_action delete|notify|delete_and_notify`

说明：
- 默认 OCR 语言为 `chi_sim+eng`，可在 `.env` 中调整。
- `ADMIN_IDS` 留空则默认所有人可用管理命令（便于初次设置），建议设置后再使用。
- 删除失败多半为权限不足，请确保机器人在群里有删除消息权限。