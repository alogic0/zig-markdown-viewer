# Math visual comparison

Compare the MathML and visual HTML backends only at an identical viewport and
rendering scale. Interactive browser tabs retain independent page zoom, which
can make a correct backend appear 20% larger when comparing 250% with 300%.

Use the native standalone renderer because it uses the same Zig renderer,
document-local directives, viewer CSS, and packaged math font as the extension.
Headless Chromium does not reliably activate an unpacked extension when opened
directly on a `file:` Markdown URL.

From the `zig-markdown-viewer` checkout:

```sh
math_compare_dir="$(mktemp -d)"
mkdir -p "${math_compare_dir}/fonts"
cp extension/css/fonts/ZigMathSTIX.woff2 \
  "${math_compare_dir}/fonts/ZigMathSTIX.woff2"

./build.sh math-dev render-html -- \
  /home/oleg/prog/docs/tst/math-mathml.md \
  -o "${math_compare_dir}/math-mathml.html"
./build.sh math-dev render-html -- \
  /home/oleg/prog/docs/tst/math-html.md \
  -o "${math_compare_dir}/math-html.html"

google-chrome --headless=new --no-sandbox --disable-gpu \
  --disable-background-networking --allow-file-access-from-files \
  --window-size=1200,1000 --force-device-scale-factor=2.5 \
  --virtual-time-budget=10000 --run-all-compositor-stages-before-draw \
  --screenshot="${math_compare_dir}/math-mathml-250.png" \
  "file://${math_compare_dir}/math-mathml.html"

google-chrome --headless=new --no-sandbox --disable-gpu \
  --disable-background-networking --allow-file-access-from-files \
  --window-size=1200,1000 --force-device-scale-factor=2.5 \
  --virtual-time-budget=10000 --run-all-compositor-stages-before-draw \
  --screenshot="${math_compare_dir}/math-html-250.png" \
  "file://${math_compare_dir}/math-html.html"
```

`--force-device-scale-factor=2.5` supplies the same deterministic 250% rendering
scale to both captures; it does not depend on a tab's persisted page-zoom
setting. Keep every other Chromium flag identical as well.

Compare these properties in order:

1. surrounding text size and inline baseline;
2. mathematical italic versus upright identifiers;
3. fraction, root, script, and operator-limit placement;
4. display-block margins and total document flow;
5. aligned-row edges and clearance between adjacent limits.

After reviewing the images, clean up with explicit targets:

```sh
rm "${math_compare_dir}/math-mathml.html" \
  "${math_compare_dir}/math-html.html" \
  "${math_compare_dir}/math-mathml-250.png" \
  "${math_compare_dir}/math-html-250.png" \
  "${math_compare_dir}/fonts/ZigMathSTIX.woff2"
rmdir "${math_compare_dir}/fonts"
rmdir "${math_compare_dir}"
```
