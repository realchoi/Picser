#!/usr/bin/env python3
"""
优化的本地化 lint 工具

改进点：
1. 搜索所有字符串字面量，而不仅仅是特定模式
2. 支持通过变量传递的本地化键
3. 支持 localized() 函数调用
4. 更准确地检测实际使用的键
"""

import json
import os
import re
import sys

# 匹配 Swift 代码中所有的字符串字面量（不在注释中）
RE_STRING_LITERAL = re.compile(r'"([^"\n\\]*(?:\\.[^"\n\\]*)*)"')

# 注释模式，用于排除注释中的字符串
RE_SINGLE_LINE_COMMENT = re.compile(r'//.*$', re.MULTILINE)
RE_MULTI_LINE_COMMENT = re.compile(r'/\*.*?\*/', re.DOTALL)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
XCSTRINGS_PATH = os.path.join(ROOT, "Languages", "Localizable.xcstrings")
SOURCE_DIRS = [os.path.join(ROOT, "Picser"), os.path.join(ROOT, "Tests")]


def load_localization_keys():
  """加载 Localizable.xcstrings 中的所有键"""
  with open(XCSTRINGS_PATH, "r", encoding="utf-8") as handler:
    raw = json.load(handler)
  strings = raw.get("strings", {})
  return set(strings.keys())


def remove_comments(content):
  """移除 Swift 代码中的注释"""
  # 先移除多行注释
  content = RE_MULTI_LINE_COMMENT.sub('', content)
  # 再移除单行注释
  content = RE_SINGLE_LINE_COMMENT.sub('', content)
  return content


def collect_string_literals():
  """收集代码中所有的字符串字面量"""
  literals = set()
  for directory in SOURCE_DIRS:
    for root, _, files in os.walk(directory):
      for filename in files:
        if not filename.endswith(".swift"):
          continue
        path = os.path.join(root, filename)
        with open(path, "r", encoding="utf-8") as handler:
          content = handler.read()

        # 移除注释，避免误报
        content = remove_comments(content)

        # 提取所有字符串字面量
        for match in RE_STRING_LITERAL.finditer(content):
          literal = match.group(1)
          # 不需要解码转义字符，直接使用原始字符串
          literals.add(literal)

  return literals


def main():
  localized_keys = load_localization_keys()
  string_literals = collect_string_literals()

  # 找出代码中使用的本地化键（字符串字面量与本地化键的交集）
  used_keys = string_literals & localized_keys

  # 找出代码中引用但在 xcstrings 中缺失的键
  # （这里我们做一个简单的启发式判断：
  #  1. 包含下划线的字符串
  #  2. 全是小写字母、数字和下划线
  #  3. 长度在 5 到 80 之间（太短或太长的不太可能是本地化键）
  #  4. 不包含空格或特殊字符）
  potential_keys = {
    s for s in string_literals
    if '_' in s
    and s.replace('_', '').replace('0', '').replace('1', '').replace('2', '').replace('3', '').replace('4', '').replace('5', '').replace('6', '').replace('7', '').replace('8', '').replace('9', '').isalpha()
    and s.islower()
    and 5 <= len(s) <= 80
    and ' ' not in s
  }
  missing = sorted(potential_keys - localized_keys)

  # 找出未使用的本地化键
  unused = sorted(localized_keys - used_keys)

  # 统计信息
  print(f"📊 统计信息：")
  print(f"  - 本地化键总数: {len(localized_keys)}")
  print(f"  - 代码中使用的键: {len(used_keys)}")
  print(f"  - 未使用的键: {len(unused)}")
  print()

  if not missing and not unused:
    print("✅ 本地化检查通过！所有键都已同步。")
    return 0

  if missing:
    print("❌ 代码中引用但在 Localizable.xcstrings 中缺失的键：")
    for key in missing:
      print(f"  - {key}")
    print()

  if unused:
    print("⚠️  在 Localizable.xcstrings 中定义但未使用的键：")
    for key in unused:
      print(f"  - {key}")
    print()
    print("💡 提示：这些键可能通过变量间接使用，请手动确认后再删除。")

  return 1 if missing else 0


if __name__ == "__main__":
  sys.exit(main())
