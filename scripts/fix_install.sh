#!/usr/bin/env bash

# 🚀 Telegram 广告管理机器人 - 快速修复脚本
# 解决交互式输入问题

echo "🔧 检测到交互式输入问题，正在修复..."

# 检查当前脚本
if [[ -f "scripts/simple_install.sh" ]]; then
    echo "✅ 找到简化安装脚本，建议使用它来避免交互式问题"
    echo
    echo "请运行以下命令："
    echo "sudo bash scripts/simple_install.sh"
    echo
    echo "或者，如果您想继续使用原来的脚本，请尝试："
    echo "sudo bash -i scripts/oneclick_install.sh"
    echo
else
    echo "❌ 未找到简化安装脚本"
    echo "请检查脚本文件是否存在"
fi

# 显示问题诊断
echo "🔍 问题诊断："
echo "• 原脚本可能在非交互式环境中运行"
echo "• 或者遇到了输入重定向问题"
echo "• 建议使用简化版本或直接运行脚本文件"
echo

# 提供解决方案
echo "💡 解决方案："
echo "1. 使用简化安装脚本（推荐）"
echo "2. 直接运行脚本文件而不是通过 curl"
echo "3. 设置环境变量后运行"
echo

echo "🚀 准备就绪！请选择上述任一方案继续安装。"