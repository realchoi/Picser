#!/usr/bin/env python3

import json
import os
import re
import sys

RE_SWIFT_KEY = re.compile(r'L10n\.(?:string|key)\("([^"]+)"')
RE_TEXT_KEY = re.compile(r'Text\s*\(\s*l10n:\s*"([^"]+)"')

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
XCSTRINGS_PATH = os.path.join(ROOT, "Languages", "Localizable.xcstrings")
SOURCE_DIRS = [os.path.join(ROOT, "Picser"), os.path.join(ROOT, "Tests")]


def load_localization_keys():
  with open(XCSTRINGS_PATH, "r", encoding="utf-8") as handler:
    raw = json.load(handler)
  strings = raw.get("strings", {})
  return set(strings.keys())


def collect_code_keys():
  keys = set()
  for directory in SOURCE_DIRS:
    for root, _, files in os.walk(directory):
      for filename in files:
        if not filename.endswith(".swift"):
          continue
        path = os.path.join(root, filename)
        with open(path, "r", encoding="utf-8") as handler:
          content = handler.read()
        keys.update(RE_SWIFT_KEY.findall(content))
        keys.update(RE_TEXT_KEY.findall(content))
  return keys


def main():
  localized_keys = load_localization_keys()
  code_keys = collect_code_keys()

  missing = sorted(code_keys - localized_keys)
  unused = sorted(localized_keys - code_keys)

  if not missing and not unused:
    print("✅ Localization lint passed. All keys are in sync.")
    return 0

  if missing:
    print("❌ Missing entries in Localizable.xcstrings:")
    for key in missing:
      print(f"  - {key}")

  if unused:
    print("⚠️ Unused localization keys:")
    for key in unused:
      print(f"  - {key}")

  return 1 if missing else 0


if __name__ == "__main__":
  sys.exit(main())
