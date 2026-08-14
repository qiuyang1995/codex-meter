#!/usr/bin/env python3
"""从 AppIcon.iconset 直接组装 AppIcon.icns。

iconutil 会把 pngquant 压缩后的调色板 PNG 重新编码成 32 位，导致体积膨胀；
本脚本把压缩后的 PNG 原样写入 icns 块，保持最小体积。
用法: python3 Scripts/make-icns.py <iconset目录> <输出.icns>
"""
import struct
import sys
from pathlib import Path

# iconset 文件名 -> icns 块类型
CHUNK_TYPES = {
    "icon_16x16.png": b"icp4",
    "icon_16x16@2x.png": b"ic11",
    "icon_32x32.png": b"icp5",
    "icon_32x32@2x.png": b"ic12",
    "icon_128x128.png": b"ic07",
    "icon_128x128@2x.png": b"ic13",
    "icon_256x256.png": b"ic08",
    "icon_256x256@2x.png": b"ic14",
    "icon_512x512.png": b"ic09",
    "icon_512x512@2x.png": b"ic10",
}


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    iconset = Path(sys.argv[1])
    output = Path(sys.argv[2])

    chunks = b""
    for name, chunk_type in CHUNK_TYPES.items():
        path = iconset / name
        if not path.exists():
            continue
        data = path.read_bytes()
        chunks += chunk_type + struct.pack(">I", len(data) + 8) + data

    output.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)
    print(f"{output}: {output.stat().st_size / 1024:.0f}K")


if __name__ == "__main__":
    main()
