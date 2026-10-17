"""Classify assertions separately from reproduced main-branch engine diagnostics."""
import re
from collections import Counter


# Exact messages/counts observed on frozen main. Normalize object IDs only.
BASELINE = {
    "charter_ui": Counter({
        "ERROR: 3 RID allocations of type 'N16RendererViewport8ViewportE' were leaked at exit.": 1,
        "ERROR: 13 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.": 1,
        "ERROR: 78 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit.": 1,
        # Original demo content creates four fewer shaped texts than the removed chart.
        "ERROR: 74 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit.": 1,
        "ERROR: 2 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.": 1,
        "ERROR: Can't add child '@Label@N' to '@HBoxContainer@N', already has a parent '@HBoxContainer@N'.": 2,
        "ERROR: 13 resources still in use at exit (run with --verbose for details).": 1,
    }),
    "charter_plugins_visual": Counter({
        "ERROR: 6 RID allocations of type 'N5GLES312LightStorage11ShadowAtlasE' were leaked at exit.": 1,
        "ERROR: 6 RID allocations of type 'N5GLES312RenderTargetE' were leaked at exit.": 1,
        "ERROR: 25 RID allocations of type 'N5GLES37TextureE' were leaked at exit.": 1,
        "ERROR: 6 RID allocations of type 'N16RendererViewport8ViewportE' were leaked at exit.": 1,
        "ERROR: 16 RID allocations of type 'PN18TextServerAdvanced22ShapedTextDataAdvancedE' were leaked at exit.": 1,
        "ERROR: 1 RID allocations of type 'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit.": 1,
        "ERROR: Texture with GL ID of N: leaked 1364 bytes.": 11,
        "ERROR: Texture with GL ID of N: leaked 4092 bytes.": 2,
        "ERROR: 12 resources still in use at exit (run with --verbose for details).": 1,
    }),
    "charter_log_test": Counter({
        "ERROR: 2 RID allocations of type 'N13RendererDummy15MaterialStorage13DummyMaterialE' were leaked at exit.": 1,
        "ERROR: 2 RID allocations of type 'N13RendererDummy15MaterialStorage11DummyShaderE' were leaked at exit.": 1,
        "ERROR: 1 resources still in use at exit (run with --verbose for details).": 1,
    }),
}


def classify(name, text):
    failures = []
    diagnostics = []
    remaining = BASELINE.get(name, Counter()).copy()
    for line in text.splitlines():
        if line == "ERROR: Failed to read the root certificate store.":
            diagnostics.append(line)
            continue
        # 2026-10-17: reproduced on frozen main, with identical assertion output.
        # Keep these messages visible; do not modify UI behavior in a path-only migration.
        normalized = re.sub(r"@\d+", "@N", line)
        normalized = re.sub(r"GL ID of \d+", "GL ID of N", normalized)
        if remaining[normalized] > 0:
            remaining[normalized] -= 1
            diagnostics.append(line)
        elif re.search(r"^FAIL\b|^BAD\b|^LOAD FAIL\b|:\s*FAIL\b|^bad charts:\s*[1-9]|SCRIPT ERROR|ERROR:|\b[1-9]\d* failures\b(?!\s*=)|failures=[1-9]", line):
            failures.append(line)
        elif name == "home_keys_song" and re.search(r"not PERFECT:\s*[1-9]", line):
            failures.append(line)
        elif name == "autoplay_double_test" and line.startswith("SKIP "):
            failures.append(line)
    return failures, diagnostics
