-- SPDX-License-Identifier: AGPL-3.0-only

local ImageSpike = {}

ImageSpike.HTML_FILENAME = "gate5-relative-assets-v1.html"
ImageSpike.ASSET_DIRNAME = "gate5-assets"
ImageSpike.ASSET_FILENAME = "gate5-test.svg"
ImageSpike.ASSET_RELATIVE_PATH = ImageSpike.ASSET_DIRNAME .. "/" .. ImageSpike.ASSET_FILENAME

function ImageSpike.svg()
    return [[<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="600" height="320" viewBox="0 0 600 320">
  <rect x="8" y="8" width="584" height="304" fill="white" stroke="black" stroke-width="16"/>
  <line x1="35" y1="45" x2="565" y2="275" stroke="black" stroke-width="18"/>
  <line x1="565" y1="45" x2="35" y2="275" stroke="black" stroke-width="18"/>
  <rect x="145" y="112" width="310" height="96" fill="white" stroke="black" stroke-width="8"/>
  <text x="300" y="177" text-anchor="middle" font-family="sans-serif" font-size="54" font-weight="bold">GATE 5</text>
</svg>]]
end

function ImageSpike.html()
    return string.format([[<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Gate 5 relative image asset spike</title>
<style>
body { line-height: 1.45; }
img { max-width: 100%%; height: auto; display: block; margin: 1em auto; }
.test-box { border: 2px solid black; padding: 0.6em; margin: 1em 0; }
</style>
</head>
<body>
<h1>Gate 5: relative local image asset</h1>
<p class="test-box"><strong>TEXT BEFORE IMAGE — must remain readable.</strong></p>
<p>The next image is a local SVG referenced by the relative path <code>%s</code>.</p>
<img src="%s" alt="Gate 5 relative local image">
<p class="test-box"><strong>TEXT AFTER LOCAL IMAGE — must remain readable.</strong></p>
<p>The next image intentionally does not exist. Its failure must not crash or make the surrounding text unusable.</p>
<img src="%s/missing-on-purpose.svg" alt="Intentionally missing Gate 5 image">
<p class="test-box"><strong>TEXT AFTER MISSING IMAGE — if you can read this, failure tolerance is usable.</strong></p>
</body>
</html>]], ImageSpike.ASSET_RELATIVE_PATH, ImageSpike.ASSET_RELATIVE_PATH, ImageSpike.ASSET_DIRNAME)
end

return ImageSpike
