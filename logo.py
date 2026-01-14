import os
import cairosvg
from PIL import Image
import io

# --- CONFIGURATION ---
# Path to your Flutter Android resources
PROJECT_PATH = "android/app/src/main/res"

# Input logo (Your awesome SVG file)
INPUT_IMAGE = "logo.svg"

# Output icon name (Standard Android launcher name)
ICON_NAME = "ic_launcher.png"

# Icon sizes for Android (Standard DPI buckets)
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

def generate_icons():
    # 1. Validation
    if not os.path.exists(INPUT_IMAGE):
        print(f"❌ Error: '{INPUT_IMAGE}' not found in the current directory.")
        return

    print(f"🚀 Starting icon generation from {INPUT_IMAGE}...")

    # 2. Processing
    try:
        for folder, size in SIZES.items():
            # Create the destination directory if it doesn't exist
            out_dir = os.path.join(PROJECT_PATH, folder)
            if not os.path.exists(out_dir):
                os.makedirs(out_dir)
                print(f"📁 Created directory: {folder}")

            output_path = os.path.join(out_dir, ICON_NAME)

            # Convert SVG to PNG at the specific size
            # We use cairosvg to ensure vector-perfect scaling
            cairosvg.svg2png(
                url=INPUT_IMAGE, 
                write_to=output_path, 
                output_width=size, 
                output_height=size
            )

            print(f"✅ Saved: {folder}/{ICON_NAME} ({size}x{size})")

        print("\n✨ All icons generated successfully for Android!")
        
    except Exception as e:
        print(f"⚠️ An error occurred: {e}")

if __name__ == "__main__":
    generate_icons()
