#!/usr/bin/env bash
set -euo pipefail

if command -v tesseract >/dev/null 2>&1; then
  echo "tesseract already installed: $(tesseract --version | head -n1)"
  exit 0
fi

if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get update -y
  sudo apt-get install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra
  echo "Installed tesseract via apt-get"
  exit 0
fi

echo "Please install Tesseract OCR manually for your distribution. For Debian/Ubuntu: apt-get install tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-chi-tra"
exit 1