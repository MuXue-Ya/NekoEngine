#!/usr/bin/env python3
"""ASTC 回填脚本：
把 astc-compressor 输出目录(astc-textures)里的 .astc 放到 assets 对应位置，
并删除已压缩的原 .png。excludes 表中未被压缩的 .png 自然保留。

用法: python3 scripts/astc_backfill.py [astc_root=astc-textures] [assets_root=assets]
映射规则: <astc_root>/assets/<rel>.astc  ->  <assets_root>/<rel>.astc
"""
import os, sys, shutil

def main():
    astc_root = sys.argv[1] if len(sys.argv) > 1 else 'astc-textures'
    assets_root = sys.argv[2] if len(sys.argv) > 2 else 'assets'
    if not os.path.isdir(astc_root):
        print('[astc-backfill] 输出目录 %s 不存在, 中止' % astc_root)
        sys.exit(1)
    moved = warned = 0
    for dirpath, _, files in os.walk(astc_root):
        for fn in files:
            if not fn.endswith('.astc'):
                continue
            src = os.path.join(dirpath, fn)
            rel = os.path.relpath(src, astc_root).replace(os.sep, '/')
            if not rel.startswith('assets/'):
                print('[astc-backfill] 警告: 非预期结构 %s' % rel)
                warned += 1
                continue
            dst = os.path.join(assets_root, rel[len('assets/'):])
            png = dst[:-len('.astc')] + '.png'
            if os.path.exists(png):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(src, dst)
                os.remove(png)
                moved += 1
            else:
                print('[astc-backfill] 警告: 未找到对应 png %s' % png)
                warned += 1
    print('[astc-backfill] 完成: 替换 %d 张, 警告 %d' % (moved, warned))
    if moved == 0:
        print('[astc-backfill] 错误: 一张都没替换, 中止构建以免打包原样 PNG')
        sys.exit(1)

if __name__ == '__main__':
    main()
