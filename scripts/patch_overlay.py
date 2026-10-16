import os
import glob

def patch_flutter_overlay_window():
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    pattern = os.path.join(local_app_data, "Pub", "Cache", "hosted", "pub.dev", "flutter_overlay_window-*", "android", "src", "main", "java", "flutter", "overlay", "window", "flutter_overlay_window", "OverlayService.java")
    matches = glob.glob(pattern)
    if not matches:
        print("No flutter_overlay_window found in pub cache.")
        return

    for path in matches:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        # Check if already patched
        if "szWindow.x / 2 + (overlayWidth / 2)" in content or "(szWindow.x / 2) + (overlayWidth / 2)" in content:
            print(f"Already patched: {path}")
            continue

        target = "int maxRightOffset = rightBound - (szWindow.x / 2) - (overlayWidth - minVisibleWidth);"
        replacement = "int maxRightOffset = rightBound - (szWindow.x / 2) + (overlayWidth / 2) - minVisibleWidth;"
        if target in content:
            content = content.replace(target, replacement)
            content = content.replace(
                "int maxLeftOffset = leftBound - (szWindow.x / 2) + minVisibleWidth;",
                "int maxLeftOffset = leftBound - (szWindow.x / 2) - (overlayWidth / 2) + minVisibleWidth;"
            )
            content = content.replace(
                "int maxBottomOffset = topBound + overlayHeight - minVisibleHeight;\n            int originalY = params.y;\n            params.y = Math.min(maxBottomOffset, params.y);",
                "int minTopOffset = topBound - overlayHeight + minVisibleHeight;\n            int maxBottomOffset = bottomBound - minVisibleHeight;\n            int originalY = params.y;\n            params.y = Math.max(minTopOffset, Math.min(maxBottomOffset, params.y));"
            )
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"Successfully patched: {path}")

if __name__ == "__main__":
    patch_flutter_overlay_window()
