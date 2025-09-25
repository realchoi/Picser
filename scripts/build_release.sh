#!/usr/bin/env bash

set -euo pipefail

# 1. 加载外部 env 文件（默认 .env.local，也可自定义）
ENV_FILE="${1:-.env.local}"
if [ -f "$ENV_FILE" ]; then
  echo "Loading environment from $ENV_FILE"
  set -a          # 自动导出变量
  source "$ENV_FILE"
  set +a
fi

# 读取参数
CONFIG=${2:-Release}
SCHEME=${3:-Pixor}
ARCHIVE_PATH=${4:-"$(pwd)/build/Pixor.xcarchive"}
EXPORT_PATH=${5:-"$(pwd)/build/Export"}
EXPORT_OPTIONS_PLIST=${6:-"Build/exportOptions.plist"}

# 内购相关变量，可视需要覆盖
export PIXOR_IAP_PRODUCT_ID=${PIXOR_IAP_PRODUCT_ID:-"com.soyotube.Picser.full"}
export PIXOR_IAP_SHARED_SECRET=${PIXOR_IAP_SHARED_SECRET:-""}
export PIXOR_ENABLE_RECEIPT_VALIDATION=${PIXOR_ENABLE_RECEIPT_VALIDATION:-0}

echo "Using product id: $PIXOR_IAP_PRODUCT_ID"
echo "Receipt validation enabled: $PIXOR_ENABLE_RECEIPT_VALIDATION"

# 你可以在这里导入本地证书，或假设 Xcode 已经配置好签名
xcodebuild -project Pixor.xcodeproj \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -archivePath "$ARCHIVE_PATH" \
           archive

xcodebuild -exportArchive \
           -archivePath "$ARCHIVE_PATH" \
           -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
           -exportPath "$EXPORT_PATH"

echo "Exported app to $EXPORT_PATH"
