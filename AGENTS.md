# Agent & AI Workspace Context

This file is intended for AI coding assistants (GitHub Copilot, Codex, Claude, etc.)
working in this repository. It records verified research findings that should inform
any future dependency or code decisions.

---

## Pillow version requirement

`requirements.txt` pins `Pillow>=12.2.0`. This is the minimum safe version for
this project. **Do not relax this bound** without reviewing the migration notes below.

---

## Pillow 9.5.0 → 12.2.0: Verified Breaking-Change Reference

Researched against primary sources: pillow.readthedocs.io release notes for
10.0.0, 10.1.0, 10.2.0, 10.3.0, 11.0.0, 12.0.0, and the deprecations page
(all verified May 2026).

### Scope within this repository

None of the installer scripts in this repo (`adafruit-pitft.py`,
`raspi-spi-reassign.py`) import or call Pillow directly.  Pillow is listed in
`requirements.txt` only so OSV-Scanner can audit it for CVEs.  The actual
runtime consumer on the target Raspberry Pi is `adafruit-circuitpython-rgb-display`,
whose core `rgb.py` uses only `image.convert()`, `img.mode` (read), `img.rotate()`,
`img.size`, and `img.getpixel()` — all stable across every version in the 10–12 range.

---

### 10.0.0 (2023-07-01) — the one hard breaking wall

All of the items below were **removed** (not merely deprecated); code using them
raises `AttributeError` at runtime.

#### Text measurement API (most common hit in TFT display code)

| Removed | Replacement |
|---|---|
| `FreeTypeFont.getsize(text)` | `FreeTypeFont.getbbox(text)` → `(l,t,r,b)`, width = `r-l` |
| `FreeTypeFont.getoffset(text)` | `FreeTypeFont.getbbox(text)` → offset is `(l, t)` |
| `FreeTypeFont.getsize_multiline(text)` | `ImageDraw.multiline_textbbox((0,0), text, font)` |
| `ImageFont.getsize(text)` | `ImageFont.getbbox(text)` / `getlength(text)` |
| `TransposedFont.getsize(text)` | `TransposedFont.getbbox(text)` / `getlength(text)` |
| `ImageDraw.textsize(text, font)` | `ImageDraw.textbbox((0,0), text, font)` + derive w/h |
| `ImageDraw.multiline_textsize(text, font)` | `ImageDraw.multiline_textbbox((0,0), text, font)` |
| `ImageDraw2.Draw.textsize(text, font)` | `ImageDraw2.Draw.textbbox((0,0), text, font)` |

> **Important**: the old `getsize` height included the vertical offset above the
> baseline; `getbbox` separates this as the `top` value. Text-centering code must
> be updated accordingly, or use text `anchor="mm"` instead.

#### Resampling constants (second most common hit in resize code)

| Removed | Replacement |
|---|---|
| `Image.ANTIALIAS` | `Image.LANCZOS` or `Image.Resampling.LANCZOS` |
| `Image.LINEAR` | `Image.BILINEAR` or `Image.Resampling.BILINEAR` |
| `Image.CUBIC` | `Image.BICUBIC` or `Image.Resampling.BICUBIC` |

#### Other removals in 10.0.0

| Removed | Replacement / notes |
|---|---|
| `im.category`, `Image.NORMAL/SEQUENCE/CONTAINER` | `getattr(im, "is_animated", False)` |
| `FitsStubImagePlugin` | `FitsImagePlugin` (no handler needed) |
| `ImageShow.Viewer.show_file(file=…)` kwarg | Renamed to `path=` |
| `JpegImagePlugin.convert_dict_qtables` | Was a no-op since 8.3.0; remove calls |
| `ImagePalette(size=…)` | Drop the `size` kwarg |
| `Image.coerce_e()` | Undocumented internal; remove calls |
| `FreeTypeFont.getmask2(fill=…)` | Undocumented; drop the kwarg |
| `PhotoImage.paste(box=…)` | Unused; drop the kwarg |
| PyQt5 / PySide2 in `ImageQt` | Upgrade to PyQt6 / PySide6 |
| `ImageCms.INTENT_*`, `ImageCms.DIRECTION_*` | `ImageCms.Intent.*`, `ImageCms.Direction.*` |
| `ImageFont.LAYOUT_BASIC/RAQM` | `ImageFont.Layout.BASIC/RAQM` |
| Several `BlpImagePlugin.*`, `FtexImagePlugin.*`, `PngImagePlugin.APNG_*` constants | Corresponding `enum` classes (see 10.0.0 notes) |

---

### 10.1.0 (2023-10-15) — no removals, two new exceptions

| Change | Notes |
|---|---|
| `im.mode = "…"` (direct attribute set) now raises `AttributeError` | Was silently ignored; use `.convert()` |
| Setting `im.mode` read-only enforced | Same as above |

New additions (backwards compatible): `has_transparency_data`, `ImageOps.cover`,
`ImageFont.load_default(size=N)`, `font_size=` arg on draw text methods.

---

### 10.2.0 (2024-01-02) — no removals, one new exception

| Change | Notes |
|---|---|
| `FreeTypeFont(size=0)` or `size<0` raises `ValueError` | Previously produced unusable object |
| `ImageMath.eval()` environment key validation | CVE-2023-50447: keys matching builtins or containing `__` raise `ValueError` |

Deprecated (not yet removed): `ImageFile.raise_oserror()`, `IptcImageFile.dump/i/PAD`.

---

### 10.3.0 (2024-04-01) — no removals, new deprecations

| Deprecated (removed in 12.0.0) | Replacement |
|---|---|
| `ImageMath.eval()` | `ImageMath.lambda_eval()` (safer) or `ImageMath.unsafe_eval()` |
| `ImageCms.FLAGS["…"]` dict | `ImageCms.Flags.*` enum (full mapping in 10.3.0 release notes) |
| `ImageCms.DESCRIPTION`, `ImageCms.VERSION` | No replacement / `PIL.__version__` |
| `ImageCms.versions()` | `PIL.features.version_module(feature="littlecms2")` |

Security fix: CVE-2024-28219 buffer overflow in `_imagingcms.c` — fixed in 10.3.0.

---

### 11.0.0 (2024-10-15) — additional removals

| Removed | Replacement |
|---|---|
| `PyAccess`, `Image.USE_CFFI_ACCESS` | Pillow C API used automatically (now faster on PyPy too) |
| `PSFile` | Internal helper only; trivial to reimplement if needed |
| `TiffImagePlugin.IFD_LEGACY_API` | Unused setting, remove references |

---

### 12.0.0 (2025-10-15) — additional removals

| Removed | Replacement |
|---|---|
| `ImageMath.eval()` | `ImageMath.lambda_eval()` / `ImageMath.unsafe_eval()` |
| `ImageMath.lambda_eval/unsafe_eval(options=…)` kwarg | Use keyword arguments directly |
| `BGR;15`, `BGR;16`, `BGR;24` image modes | Experimental, use standard RGB modes |
| `Image.isImageType(im)` | `isinstance(im, Image.Image)` |
| `ImageFile.raise_oserror()` | Internal only; not used in application code |
| `ImageDraw.getdraw(hints=…)` | Drop the `hints` kwarg |
| `IptcImageFile.dump`, `.i`, `.PAD` | Internal helpers |
| `ImageCms.FLAGS[…]` | `ImageCms.Flags.*` enum |
| `JpegImageFile.huffman_ac`, `.huffman_dc` | Were unused dicts; remove all references |
| `features.check("transp_webp"/"webp_mux"/"webp_anim")` | `features.check("webp")` |
| `Image.core.ImagingCore.id`, `.unsafe_ptrs` | `Image.Image.getim()` returns a Capsule |
| ICNS `(width, height, scale)` size tuple | `image.load(scale)` |

---

### Summary: what actually needs changing when migrating user application code

1. **Text measurement** (`getsize` → `getbbox`): the single largest source of
   breakage in TFT/display example code. Note that `getbbox` returns
   `(left, top, right, bottom)`; width = `right - left`, height = `bottom - top`,
   and `top` is a separate offset that `getsize` used to fold into `height`.
2. **Resampling constants** (`ANTIALIAS` → `LANCZOS`): one-word substitution.
3. **`ImageMath.eval()`** → `lambda_eval()` if you need safety, `unsafe_eval()` otherwise.
4. Everything else is either undocumented internals or specialised plugin code.

