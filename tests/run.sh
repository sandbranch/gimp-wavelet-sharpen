#!/bin/sh
# Builds the plug-in into tests/output and runs it inside the Flatpak GIMP
# without a window, with a gimprc that adds that folder to the plug-in path
# (the installed plug-ins are not touched), then checks that it steepens
# edges and keeps flat areas. Needs gimp-plugin-devtools next to this repo.
# Close GIMP first.
set -e
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
out="$here/output"
build="$top/../gimp-plugin-devtools/gimp-build.sh"
rm -rf "$out"; mkdir -p "$out"
"$build" "$top" meson setup "$out/build" -Dplugindir="$out/plug-ins" > "$out/build.log"
"$build" "$top" ninja -C "$out/build" install >> "$out/build.log"
python3 "$here/make-image.py" "$out/test.png"
printf '(plug-in-path "${gimp_dir}/plug-ins:${gimp_plug_in_dir}/plug-ins:%s")\n' "$out/plug-ins" > "$out/gimprc"
flatpak run --filesystem="$here" --env=WT_OUT="$out" --env=WT_PROC=plug-in-wavelet-sharpen \
  --env=WT_ARGS="amount=1 radius=0.5" \
  --command=gimp-console-3.2 org.gimp.GIMP --no-interface --no-data --gimprc="$out/gimprc" \
  --batch-interpreter python-fu-eval -b "exec(open('$here/apply.py').read())" --quit 2>&1 | grep -E "^status|Error|Traceback"
python3 - "$out" <<'PY'
import sys
import numpy as np
from PIL import Image
out = sys.argv[1]
L = lambda n: np.asarray(Image.open(out + '/' + n).convert('L')).astype(float) / 255
src, res = L('test.png'), L('result.png')
fails = 0
def check(ok, msg):
    global fails
    print(('ok   ' if ok else 'FAIL ') + msg)
    fails += not ok
s0, s1 = np.abs(np.diff(src[100, 190:210])).max(), np.abs(np.diff(res[100, 190:210])).max()
check(s1 > 1.1 * s0, 'edge slope %.3f -> %.3f' % (s0, s1))
f0, f1 = src[:, 250:390].mean(), res[:, 250:390].mean()
check(abs(f1 - f0) < 0.01, 'flat area %.3f -> %.3f' % (f0, f1))
print('%d failed' % fails)
sys.exit(fails > 0)
PY
