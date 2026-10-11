"""Export Heap icons. Requires Python 3, GdkPixbuf, and filter-capable librsvg."""

from __future__ import annotations

import ctypes
import ctypes.util
import math
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/icon-options/01-teetering-pile.svg"
ANDROID_RES = ROOT / "ui/android/app/src/main/res"
WEB_ICONS = ROOT / "ui/web/icons"
SVG_NAMESPACE = "http://www.w3.org/2000/svg"
CREAM_HEX = "#faf7f0"  # Warm cream from the selected SVG.
CREAM_RGB = bytes((250, 247, 240))  # Same cream in RGB channel order.
OUTPUT_SIZE = 1024  # Declared SVG export and nodpi artwork size.
ANDROID_SAFE_RADIUS = 33 / 108  # 66dp safe circle on a 108dp adaptive layer.
GDK_INTERP_HYPER = 3  # GdkPixbuf's highest-quality downsampling mode.
WEB_SAFE_RADIUS = 0.4  # Web maskable icons reserve the outer 20%.
SOURCE_VIEW_BOX = "0 0 512 512"  # The selected SVG's 512-unit viewBox.
ANDROID_FOREGROUND_VIEW_BOX = "-45 -31 600 600"  # Preserves the selected 55% width.
WEB_MASKABLE_VIEW_BOX = "-64 -64 640 640"  # Fits web artwork inside its safe circle.
ANDROID_DENSITIES = (
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
)  # Standard Android launcher density dimensions.
WEB_ICON_SIZES = (
    ("heap-32.png", 32),
    ("heap-192.png", 192),
    ("heap-512.png", 512),
)  # Sizes wired by the current web favicon and manifest.
WEB_MASKABLE_SIZE = 512  # Existing maskable manifest icon size.


class GError(ctypes.Structure):
    _fields_ = [
        ("domain", ctypes.c_uint),
        ("code", ctypes.c_int),
        ("message", ctypes.c_char_p),
    ]


def load_pixbuf_library() -> tuple[ctypes.CDLL, ctypes.CDLL]:
    """Load librsvg for rendering and GdkPixbuf for scaling and PNG checks."""
    library_path = ctypes.util.find_library("gdk_pixbuf-2.0")
    rsvg_path = ctypes.util.find_library("rsvg-2")
    if library_path is None or rsvg_path is None:
        raise RuntimeError("Install GdkPixbuf and librsvg before exporting icons.")

    pixbuf = ctypes.CDLL(library_path)
    rsvg = ctypes.CDLL(rsvg_path)
    rsvg.rsvg_handle_new_from_file.argtypes = [
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.POINTER(GError)),
    ]
    rsvg.rsvg_handle_new_from_file.restype = ctypes.c_void_p
    rsvg.rsvg_handle_get_pixbuf.argtypes = [ctypes.c_void_p]
    rsvg.rsvg_handle_get_pixbuf.restype = ctypes.c_void_p
    pixbuf.gdk_pixbuf_scale_simple.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
    ]
    pixbuf.gdk_pixbuf_scale_simple.restype = ctypes.c_void_p
    pixbuf.gdk_pixbuf_new_from_file.argtypes = [
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.POINTER(GError)),
    ]
    pixbuf.gdk_pixbuf_new_from_file.restype = ctypes.c_void_p
    pixbuf.gdk_pixbuf_savev.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_char_p),
        ctypes.POINTER(ctypes.c_char_p),
        ctypes.POINTER(ctypes.POINTER(GError)),
    ]
    pixbuf.gdk_pixbuf_savev.restype = ctypes.c_int
    pixbuf.gdk_pixbuf_get_width.argtypes = [ctypes.c_void_p]
    pixbuf.gdk_pixbuf_get_width.restype = ctypes.c_int
    pixbuf.gdk_pixbuf_get_height.argtypes = [ctypes.c_void_p]
    pixbuf.gdk_pixbuf_get_height.restype = ctypes.c_int
    pixbuf.gdk_pixbuf_get_n_channels.argtypes = [ctypes.c_void_p]
    pixbuf.gdk_pixbuf_get_n_channels.restype = ctypes.c_int
    pixbuf.gdk_pixbuf_get_has_alpha.argtypes = [ctypes.c_void_p]
    pixbuf.gdk_pixbuf_get_has_alpha.restype = ctypes.c_int
    pixbuf.gdk_pixbuf_get_rowstride.argtypes = [ctypes.c_void_p]
    pixbuf.gdk_pixbuf_get_rowstride.restype = ctypes.c_int
    pixbuf.gdk_pixbuf_get_pixels.argtypes = [ctypes.c_void_p]
    pixbuf.gdk_pixbuf_get_pixels.restype = ctypes.POINTER(ctypes.c_ubyte)
    pixbuf.g_object_unref.argtypes = [ctypes.c_void_p]
    return pixbuf, rsvg


def error_message(error: ctypes.POINTER(GError), operation: str) -> None:
    """Raise a readable error when librsvg or GdkPixbuf reports a failure."""
    if error:
        message = error.contents.message.decode("utf-8", errors="replace")
        raise RuntimeError(f"{operation}: {message}")


def render_svg(
    pixbuf: ctypes.CDLL,
    rsvg: ctypes.CDLL,
    source: Path,
    destination: Path,
    size: int,
) -> None:
    """Render an SVG file into a square PNG at the requested pixel size."""
    error = ctypes.POINTER(GError)()
    handle = rsvg.rsvg_handle_new_from_file(str(source).encode(), ctypes.byref(error))
    error_message(error, f"Could not read {source}")
    original = rsvg.rsvg_handle_get_pixbuf(handle)
    image = pixbuf.gdk_pixbuf_scale_simple(original, size, size, GDK_INTERP_HYPER)
    if not image:
        raise RuntimeError(f"Could not resize {source}")
    saved = pixbuf.gdk_pixbuf_savev(
        image,
        str(destination).encode(),
        b"png",
        None,
        None,
        ctypes.byref(error),
    )
    error_message(error, f"Could not write {destination}")
    pixbuf.g_object_unref(image)
    pixbuf.g_object_unref(original)
    pixbuf.g_object_unref(handle)
    if not saved:
        raise RuntimeError(f"Could not write {destination}")


def load_png(pixbuf: ctypes.CDLL, path: Path, size: int) -> int:
    """Load a PNG at native resolution and reject dimensions that do not match."""
    error = ctypes.POINTER(GError)()
    image = pixbuf.gdk_pixbuf_new_from_file(str(path).encode(), ctypes.byref(error))
    error_message(error, f"Could not verify {path}")
    dimensions = (
        pixbuf.gdk_pixbuf_get_width(image),
        pixbuf.gdk_pixbuf_get_height(image),
    )
    if dimensions != (size, size):
        pixbuf.g_object_unref(image)
        raise RuntimeError(
            f"Unexpected dimensions in {path}: {dimensions[0]}x{dimensions[1]}"
        )
    return image


def verify_png(
    pixbuf: ctypes.CDLL,
    path: Path,
    size: int,
    foreground: bool = False,
    background: bool = False,
) -> None:
    """Check image dimensions, adaptive transparency, and cream background pixels."""
    image = load_png(pixbuf, path, size)
    channels = pixbuf.gdk_pixbuf_get_n_channels(image)
    rowstride = pixbuf.gdk_pixbuf_get_rowstride(image)
    pixels = pixbuf.gdk_pixbuf_get_pixels(image)
    if foreground:
        if not pixbuf.gdk_pixbuf_get_has_alpha(image) or channels != 4:
            raise RuntimeError(f"Foreground is not RGBA: {path}")
        alpha_values = [
            pixels[y * rowstride + x * channels + 3]
            for y in range(size)
            for x in range(size)
        ]
        opaque_pixels = [index for index, alpha in enumerate(alpha_values) if alpha]
        corners = (0, size - 1, size * (size - 1), size * size - 1)
        if not opaque_pixels or any(alpha_values[index] for index in corners):
            raise RuntimeError(f"Foreground transparency check failed for {path}")
        width_fraction = (
            max(index % size for index in opaque_pixels)
            - min(index % size for index in opaque_pixels)
            + 1
        ) / size
        # Allow rasterization edges around the selected 55% width.
        if not 0.53 <= width_fraction <= 0.58:
            raise RuntimeError(
                f"Foreground footprint is {width_fraction:.1%}, expected about 55%"
            )
    if background:
        if channels < 3:
            raise RuntimeError(f"Image has no RGB channels: {path}")
        pixel = bytes(pixels[index] for index in range(3))
        if pixel != CREAM_RGB:
            raise RuntimeError(
                f"Unexpected cream background pixel in {path}: {pixel!r}"
            )
        if pixbuf.gdk_pixbuf_get_has_alpha(image):
            alpha = pixels[3]
            if alpha != 255:
                raise RuntimeError(
                    f"Icon background is not opaque in {path}: alpha {alpha}"
                )
    pixbuf.g_object_unref(image)


def verify_maskable(pixbuf: ctypes.CDLL, path: Path, size: int) -> None:
    """Ensure every drawn pixel stays inside the central 80% circular mask area."""
    image = load_png(pixbuf, path, size)
    channels = pixbuf.gdk_pixbuf_get_n_channels(image)
    rowstride = pixbuf.gdk_pixbuf_get_rowstride(image)
    pixels = pixbuf.gdk_pixbuf_get_pixels(image)
    radius = size * WEB_SAFE_RADIUS
    for y in range(size):
        for x in range(size):
            pixel = bytes(
                pixels[y * rowstride + x * channels : y * rowstride + x * channels + 3]
            )
            distance_squared = (x + 0.5 - size / 2) ** 2 + (y + 0.5 - size / 2) ** 2
            if pixel != CREAM_RGB and distance_squared > radius**2:
                raise RuntimeError(
                    f"Artwork extends beyond the mask-safe circle in {path}"
                )
    pixbuf.g_object_unref(image)


def verify_android_safe_circle(pixbuf: ctypes.CDLL, path: Path, size: int) -> None:
    """Warn when adaptive foreground alpha extends beyond Android's generic safe circle."""
    image = load_png(pixbuf, path, size)
    channels = pixbuf.gdk_pixbuf_get_n_channels(image)
    rowstride = pixbuf.gdk_pixbuf_get_rowstride(image)
    pixels = pixbuf.gdk_pixbuf_get_pixels(image)
    radius = size * ANDROID_SAFE_RADIUS
    center = size / 2
    furthest_distance_squared = 0.0
    furthest_pixel = (0, 0)
    for y in range(size):
        for x in range(size):
            alpha = pixels[y * rowstride + x * channels + 3]
            distance_squared = (x + 0.5 - center) ** 2 + (y + 0.5 - center) ** 2
            if alpha and distance_squared > furthest_distance_squared:
                furthest_distance_squared = distance_squared
                furthest_pixel = (x, y)
    pixbuf.g_object_unref(image)
    if furthest_distance_squared > radius**2:
        print(
            "Warning: Android foreground extends beyond the generic 66dp safe "
            f"circle on a 108dp layer (furthest pixel {furthest_pixel}, "
            f"{math.sqrt(furthest_distance_squared):.1f}px from center, "
            f"safe radius {radius:.1f}px); retaining "
            "the selected 55% placement. This placement targets the Pixel 6 Pro launcher.",
            file=sys.stderr,
        )


def make_variant(
    source: Path,
    view_box: str,
    transparent: bool,
    directory: Path,
    name: str,
) -> Path:
    """Create a temporary SVG variant with the requested crop and background."""
    tree = ET.parse(source)
    root = tree.getroot()
    root.set("width", str(OUTPUT_SIZE))
    root.set("height", str(OUTPUT_SIZE))
    root.set("viewBox", view_box)
    background = root.find(f"{{{SVG_NAMESPACE}}}rect")
    if background is None:
        raise RuntimeError("The SVG background rectangle was not found.")
    if transparent:
        root.remove(background)
    else:
        x, y, width, height = view_box.split()
        background.set("x", x)
        background.set("y", y)
        background.set("width", width)
        background.set("height", height)
    variant = directory / f"{name}.svg"
    tree.write(variant, encoding="utf-8", xml_declaration=True)
    return variant


def main() -> None:
    """Export Android launcher and web icons from the selected SVG master."""
    pixbuf, rsvg = load_pixbuf_library()
    ANDROID_RES.joinpath("drawable-nodpi").mkdir(parents=True, exist_ok=True)
    WEB_ICONS.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as temporary_directory:
        temporary = Path(temporary_directory)
        full_art = make_variant(SOURCE, SOURCE_VIEW_BOX, False, temporary, "full-art")
        foreground = make_variant(
            SOURCE, ANDROID_FOREGROUND_VIEW_BOX, True, temporary, "foreground"
        )
        temporary_foreground = temporary / "android-foreground.png"
        render_svg(pixbuf, rsvg, foreground, temporary_foreground, OUTPUT_SIZE)
        verify_png(pixbuf, temporary_foreground, OUTPUT_SIZE, foreground=True)
        verify_android_safe_circle(pixbuf, temporary_foreground, OUTPUT_SIZE)

        for density, size in ANDROID_DENSITIES:
            icon_path = ANDROID_RES / f"mipmap-{density}/ic_launcher.png"
            render_svg(pixbuf, rsvg, full_art, icon_path, size)
            verify_png(pixbuf, icon_path, size, background=True)
        foreground_path = ANDROID_RES / "drawable-nodpi/ic_launcher_foreground.png"
        shutil.copyfile(temporary_foreground, foreground_path)

        background = temporary / "background.svg"
        background.write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{OUTPUT_SIZE}" '
            f'height="{OUTPUT_SIZE}" viewBox="0 0 1 1">'
            f'<rect width="1" height="1" fill="{CREAM_HEX}"/></svg>',
            encoding="utf-8",
        )
        background_path = ANDROID_RES / "drawable-nodpi/ic_launcher_background.png"
        render_svg(pixbuf, rsvg, background, background_path, OUTPUT_SIZE)
        verify_png(pixbuf, background_path, OUTPUT_SIZE, background=True)

        for filename, size in WEB_ICON_SIZES:
            icon_path = WEB_ICONS / filename
            render_svg(pixbuf, rsvg, full_art, icon_path, size)
            verify_png(pixbuf, icon_path, size, background=True)

        maskable_art = make_variant(
            SOURCE, WEB_MASKABLE_VIEW_BOX, False, temporary, "maskable"
        )
        maskable_path = WEB_ICONS / "heap-512-maskable.png"
        render_svg(pixbuf, rsvg, maskable_art, maskable_path, WEB_MASKABLE_SIZE)
        verify_png(pixbuf, maskable_path, WEB_MASKABLE_SIZE, background=True)
        verify_maskable(pixbuf, maskable_path, WEB_MASKABLE_SIZE)


if __name__ == "__main__":
    main()
