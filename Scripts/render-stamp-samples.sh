#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# Usage: Scripts/render-stamp-samples.sh [output-directory] [rotation-degrees]
# Render production PDF stamp operators with Apple's PDFKit into EN/FI/SV PNGs.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-${HOME}/Desktop}"
mkdir -p "${output}" tmp/pdfs
swiftc CardCore/Sources/CardCore/PdfStampRenderer.swift \
  CardCore/Sources/CardCore/StampMark.swift \
  CardCore/Sources/CardCore/Values/PdfValues.swift \
  Scripts/RenderStampSamples.swift -o tmp/pdfs/render-stamps
tmp/pdfs/render-stamps tmp/pdfs "${@:2}"
cp tmp/pdfs/signature-stamp-*-tilted.png "${output}/"
