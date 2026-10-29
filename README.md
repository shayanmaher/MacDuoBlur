# MacDuoBlur 📖✨

Bring the iconic **iPhone Duo / Surface Duo** foldable screen hinge blur and unblur effect directly to your MacBook!

When you start closing your MacBook lid, your desktop wallpaper dynamically and progressively blurs and dims with a realistic 3D perspective fold. When you open the lid back up, it focuses back into crystal-clear sharpness.

---

## ✨ Features

- 📐 **Direct Hardware Sensor Integration:** Reads Apple's native HID lid angle sensor (`UsagePage: 0x20, Usage: 0x8A`) with 0.01° precision.
- 🔒 **Zero Permissions Needed:** Does NOT require Screen Recording or Camera permissions. No privacy indicator dots!
- 🌊 **Progressive Directional Blur:** The blur sweeps dynamically across the wallpaper like a wave as you close the lid (starts at the top half and continues down to the hinge).
- 🪟 **Subtle 3D Perspective Tilt:** Folds the wallpaper backward in 3D space matching the physical angle of your screen.
- 🔋 **Zero Battery Impact:** Automatically idles with 0% GPU / CPU overhead while your laptop is open and resting.
- 🎛️ **Full Menu Bar Control:**
  - Real-time lid angle & blur percentage readout.
  - Configurable angle trigger thresholds (Fast, Ultra-fast, or Standard).
  - Customizable blur depth (Subtle, Standard Duo, Deep Cinematic).
  - Toggle between progressive wave blur or uniform blur.
  - Option to blur behind or over desktop icons.

---

## 🚀 Download & Installation

1. Download the latest **`MacDuoBlur.dmg`** from the [Releases](https://github.com/shayanmaher/MacDuoBlur/releases) page.
2. Open the `.dmg` file and drag **`MacDuoBlur.app`** into your **`Applications`** folder.
3. Launch **MacDuoBlur**. The app will appear in your macOS menu bar.
4. Slowly tilt your MacBook lid forward to see the wallpaper blur in real time!

---

## 🛠️ Building from Source

Requires macOS 13+ with Xcode Command Line Tools (`swiftc`):

```bash
git clone https://github.com/shayanmaher/MacDuoBlur.git
cd MacDuoBlur
./build.sh
```

The compiled app and DMG will be generated in `build/MacDuoBlur.dmg`.

---

## 🇮🇷 راهنمای فارسی

برنامه **MacDuoBlur** افکت نمادین و جذاب باز و بسته شدن گوشی‌های تاشو (آیفون Duo و سرفیس Duo) را به مک‌بوک می‌آورد:

- **ماتی تدریجی و موجی:** با بستن صفحه، ابتدا نیمه بالایی والپیپر مات می‌شود و با نزدیک‌تر شدن به کیبورد، موج ماتی تمام صفحه را می‌پوشاند. با باز کردن مجدد، صفحه دوباره کاملاً شفاف (Unblur) می‌شود.
- **بدون نیاز به دسترسی:** از سنسور سخت‌افزاری زاویه لولای اپل مستقیماً استفاده می‌کند؛ بدون نیاز به دسترسی دوربین یا Screen Recording.
- **مصرف باتری نزدیک به صفر:** در حالت عادی وقتی درب لپ‌تاپ باز است، موتور گرافیکی خاموش شده و مصرف باتری ۰٪ است.

---

## 📄 License

MIT License © 2026 [Shayan Maher](https://github.com/shayanmaher)
