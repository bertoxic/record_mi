import os
import math
from PIL import Image, ImageDraw, ImageFilter

def create_minimalist_mic_icon():
    size = 512
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    
    # 1. Background: Dark sleek rounded squircle / circular backing with subtle gradient
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    
    # Rounded rectangle background
    corner_radius = 110
    bg_draw.rounded_rectangle([16, 16, size - 16, size - 16], radius=corner_radius, fill=(11, 17, 32, 255))
    
    # Subtle inner border for depth
    bg_draw.rounded_rectangle([16, 16, size - 16, size - 16], radius=corner_radius, outline=(30, 41, 59, 255), width=3)
    
    # 2. Subtle soft center glow behind microphone
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    cx, cy = size // 2, size // 2 - 10
    glow_draw.ellipse([cx - 130, cy - 130, cx + 130, cy + 130], fill=(56, 189, 248, 35))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    bg = Image.alpha_composite(bg, glow)
    
    # 3. Minimalist Microphone
    # Draw onto an overlay for crisp rendering
    mic_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mic_layer)
    
    # Colors
    cyan_bright = (56, 189, 248, 255) # #38BDF8
    white = (248, 250, 252, 255)
    accent_glow = (56, 189, 248, 180)
    
    # Dimensions for mic capsule
    cap_w = 96
    cap_h = 160
    cap_left = cx - cap_w // 2
    cap_top = cy - 120
    cap_right = cap_left + cap_w
    cap_bottom = cap_top + cap_h
    cap_radius = cap_w // 2
    
    # Draw capsule body (minimalist, clean gradient/fill)
    # Outer capsule
    draw.rounded_rectangle([cap_left, cap_top, cap_right, cap_bottom], radius=cap_radius, fill=(24, 34, 53, 255), outline=cyan_bright, width=7)
    
    # Clean grill line across capsule
    grill_y = cap_top + cap_h // 2 - 8
    draw.line([cap_left + 16, grill_y, cap_right - 16, grill_y], fill=(56, 189, 248, 200), width=4)
    draw.line([cap_left + 22, grill_y + 16, cap_right - 22, grill_y + 16], fill=(56, 189, 248, 120), width=3)
    
    # Minimalist recording dot at center of upper capsule
    dot_cy = cap_top + cap_radius - 8
    draw.ellipse([cx - 6, dot_cy - 6, cx + 6, dot_cy + 6], fill=(239, 68, 68, 255))
    
    # U-shaped cradle around capsule
    cradle_padding = 24
    c_left = cap_left - cradle_padding
    c_top = cap_top + 30
    c_right = cap_right + cradle_padding
    c_bottom = cap_bottom + cradle_padding
    
    # Draw U-bracket arc (from 0 to 180 degrees)
    arc_box = [c_left, c_top + 20, c_right, c_bottom]
    draw.arc(arc_box, start=0, end=180, fill=white, width=7)
    # Vertical arms of U-cradle
    draw.line([c_left, c_top + 30, c_left, arc_box[1] + (arc_box[3] - arc_box[1]) // 2], fill=white, width=7)
    draw.line([c_right, c_top + 30, c_right, arc_box[1] + (arc_box[3] - arc_box[1]) // 2], fill=white, width=7)
    
    # Stem from bottom of U-cradle
    stem_top = c_bottom
    stem_bottom = stem_top + 50
    draw.line([cx, stem_top, cx, stem_bottom], fill=white, width=8)
    
    # Base stand (minimalist rounded bar)
    base_w = 110
    base_h = 10
    base_top = stem_bottom
    draw.rounded_rectangle([cx - base_w // 2, base_top, cx + base_w // 2, base_top + base_h], radius=base_h // 2, fill=white)
    
    # Combine layers
    final_img = Image.alpha_composite(bg, mic_layer)
    
    # Save output to all mipmap directories
    res_base = os.path.join("android", "app", "src", "main", "res")
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    
    for folder, dim in densities.items():
        out_dir = os.path.join(res_base, folder)
        os.makedirs(out_dir, exist_ok=True)
        resized = final_img.resize((dim, dim), Image.Resampling.LANCZOS)
        
        target_path = os.path.join(out_dir, "ic_launcher.png")
        resized.save(target_path, "PNG")
        print(f"Saved: {target_path} ({dim}x{dim})")
        
        # Also round launcher
        target_round = os.path.join(out_dir, "ic_launcher_round.png")
        # Circle mask
        mask = Image.new("L", (dim, dim), 0)
        mask_draw = ImageDraw.Draw(mask)
        mask_draw.ellipse([0, 0, dim - 1, dim - 1], fill=255)
        round_img = Image.new("RGBA", (dim, dim), (0, 0, 0, 0))
        round_img.paste(resized, (0, 0), mask)
        round_img.save(target_round, "PNG")

if __name__ == "__main__":
    create_minimalist_mic_icon()
