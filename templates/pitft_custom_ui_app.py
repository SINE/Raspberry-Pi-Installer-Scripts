#!/usr/bin/env python3
"""Simple PiTFT custom UI app with image/gif area and ticker."""

import atexit
import os
import sys

import pygame
from PIL import Image, ImageSequence

WIDTH, HEIGHT = 240, 240
TICKER_HEIGHT = 32
IMAGE_HEIGHT = HEIGHT - TICKER_HEIGHT
FPS = 30

BG = (0, 0, 0)
TICKER_BG = (22, 22, 22)
TICKER_FG = (255, 220, 0)

ASSET_PATH = os.environ.get("PITFT_IMAGE", "")
TICKER_TEXT = os.environ.get("PITFT_TICKER", "PiTFT custom UI service running")


def _restore_env(key, value):
    if value is None:
        os.environ.pop(key, None)
    else:
        os.environ[key] = value


def init_display_with_fallback(size):
    """Try SDL video backends conservatively, preferring user/env choice first."""
    previous_driver = os.environ.get("SDL_VIDEODRIVER")
    tried = []

    # Order: explicit env -> auto (unset) -> kmsdrm -> fbcon -> directfb.
    candidates = [previous_driver, "", "kmsdrm", "fbcon", "directfb"]

    for candidate in candidates:
        try:
            if candidate is None:
                continue

            if candidate == "":
                os.environ.pop("SDL_VIDEODRIVER", None)
                candidate_label = "auto"
            else:
                os.environ["SDL_VIDEODRIVER"] = candidate
                candidate_label = candidate

            pygame.display.quit()
            pygame.display.init()
            screen = pygame.display.set_mode(size, pygame.FULLSCREEN)
            active = pygame.display.get_driver()
            print(f"[pitft-ui] SDL video driver active: {active} (requested {candidate_label})")
            return screen
        except pygame.error as exc:
            tried.append(f"{candidate_label}: {exc}")

    _restore_env("SDL_VIDEODRIVER", previous_driver)
    print("[pitft-ui] Failed to initialize display with available SDL drivers", file=sys.stderr)
    for msg in tried:
        print(f"[pitft-ui] {msg}", file=sys.stderr)
    raise RuntimeError("No usable SDL video backend found")


def load_frames(path, size):
    if not path or not os.path.exists(path):
        return []

    frames = []
    with Image.open(path) as img:
        for frame in ImageSequence.Iterator(img):
            frame_rgb = frame.convert("RGB").resize(size, Image.Resampling.LANCZOS)
            duration = frame.info.get("duration", 100)
            surface = pygame.image.fromstring(frame_rgb.tobytes(), size, "RGB")
            frames.append((surface, max(duration, 20)))

    return frames


def build_static_placeholder(size, font):
    surf = pygame.Surface(size)
    surf.fill((15, 15, 15))
    txt = font.render("No image configured", True, (210, 210, 210))
    surf.blit(txt, (8, (size[1] - txt.get_height()) // 2))
    return surf


def main():
    pygame.init()
    atexit.register(pygame.quit)

    screen = init_display_with_fallback((WIDTH, HEIGHT))
    pygame.mouse.set_visible(False)
    clock = pygame.time.Clock()

    font_ticker = pygame.font.Font(None, 22)
    font_placeholder = pygame.font.Font(None, 24)

    frames = load_frames(ASSET_PATH, (WIDTH, IMAGE_HEIGHT))
    fallback = build_static_placeholder((WIDTH, IMAGE_HEIGHT), font_placeholder)

    ticker_surface = font_ticker.render(f"   {TICKER_TEXT}   ", True, TICKER_FG)
    ticker_x = 0

    frame_idx = 0
    frame_elapsed_ms = 0

    running = True
    while running:
        dt = clock.tick(FPS)

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False

        screen.fill(BG)

        if frames:
            frame_elapsed_ms += dt
            frame_surface, frame_ms = frames[frame_idx]
            if frame_elapsed_ms >= frame_ms:
                frame_elapsed_ms = 0
                frame_idx = (frame_idx + 1) % len(frames)
            screen.blit(frame_surface, (0, 0))
        else:
            screen.blit(fallback, (0, 0))

        ticker_rect = pygame.Rect(0, IMAGE_HEIGHT, WIDTH, TICKER_HEIGHT)
        pygame.draw.rect(screen, TICKER_BG, ticker_rect)

        ticker_x = (ticker_x - 2) % max(1, ticker_surface.get_width())
        draw_x = -ticker_x
        while draw_x < WIDTH:
            screen.blit(ticker_surface, (draw_x, IMAGE_HEIGHT + 6))
            draw_x += ticker_surface.get_width()

        pygame.display.flip()


if __name__ == "__main__":
    main()
