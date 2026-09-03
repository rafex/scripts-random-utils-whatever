#!/usr/bin/env python3
"""Generate original retro podcast transition sounds as uncompressed WAV files."""

from __future__ import annotations

import math
import random
import wave
from pathlib import Path


SAMPLE_RATE = 44_100
TAU = math.tau


def envelope(t: float, duration: float, attack: float = 0.008, release: float = 0.08) -> float:
    """Short fades prevent clicks at the edges of synthesized sounds."""
    if t < attack:
        return t / attack
    if t > duration - release:
        return max(0.0, (duration - t) / release)
    return 1.0


def add_tone(buffer: list[float], start: float, duration: float, frequency: float,
             amplitude: float, kind: str = "sine", end_frequency: float | None = None) -> None:
    """Mix a tone or frequency sweep into a mono buffer."""
    first = max(0, int(start * SAMPLE_RATE))
    last = min(len(buffer), int((start + duration) * SAMPLE_RATE))
    phase = 0.0
    for index in range(first, last):
        t = (index / SAMPLE_RATE) - start
        ratio = min(1.0, t / duration) if duration else 1.0
        current_frequency = frequency
        if end_frequency is not None:
            current_frequency += (end_frequency - frequency) * ratio
        phase += TAU * current_frequency / SAMPLE_RATE
        if kind == "square":
            value = 1.0 if math.sin(phase) >= 0 else -1.0
        elif kind == "triangle":
            value = 2.0 * abs(2.0 * ((phase / TAU) % 1.0) - 1.0) - 1.0
        else:
            value = math.sin(phase)
        buffer[index] += amplitude * value * envelope(t, duration)


def add_noise(buffer: list[float], start: float, duration: float, amplitude: float) -> None:
    first = max(0, int(start * SAMPLE_RATE))
    last = min(len(buffer), int((start + duration) * SAMPLE_RATE))
    for index in range(first, last):
        t = (index / SAMPLE_RATE) - start
        buffer[index] += amplitude * random.uniform(-1.0, 1.0) * envelope(t, duration, 0.01, 0.12)


def write_wav(path: Path, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(sample) for sample in samples))
    scale = 0.89 / peak
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for sample in samples:
            value = max(-1.0, min(1.0, sample * scale))
            frames.extend(int(value * 32767).to_bytes(2, "little", signed=True))
        wav_file.writeframes(frames)


def modem_transition() -> list[float]:
    duration = 2.65
    buffer = [0.0] * int(duration * SAMPLE_RATE)
    # An original, compact approximation of a dial-up handshake for section changes.
    add_tone(buffer, 0.00, 0.10, 425, 0.24)
    add_tone(buffer, 0.00, 0.10, 625, 0.18)
    add_tone(buffer, 0.12, 0.18, 697, 0.25)
    add_tone(buffer, 0.12, 0.18, 1209, 0.22)
    add_tone(buffer, 0.34, 0.32, 1_500, 0.27, end_frequency=2_250)
    add_tone(buffer, 0.70, 0.14, 2_400, 0.27)
    add_tone(buffer, 0.88, 0.12, 1_200, 0.25)
    add_tone(buffer, 1.02, 0.11, 2_400, 0.24)
    add_tone(buffer, 1.15, 0.10, 1_200, 0.22)
    add_tone(buffer, 1.28, 0.35, 2_100, 0.19, end_frequency=1_050)
    add_noise(buffer, 1.64, 0.35, 0.075)
    add_tone(buffer, 1.66, 0.11, 1_800, 0.18)
    add_tone(buffer, 1.81, 0.10, 2_700, 0.18)
    add_tone(buffer, 1.96, 0.16, 1_650, 0.20, end_frequency=2_650)
    add_tone(buffer, 2.17, 0.25, 2_100, 0.16)
    add_tone(buffer, 2.47, 0.09, 3_100, 0.14)
    return buffer


def modem_variant(version: int) -> list[float]:
    """Create one of five alternative modem handshakes for comparison."""
    configurations = {
        1: {
            "duration": 2.20,
            "tones": [
                (0.00, 0.09, 425, 0.24, "sine", None),
                (0.00, 0.09, 625, 0.18, "sine", None),
                (0.13, 0.16, 697, 0.24, "sine", None),
                (0.13, 0.16, 1_209, 0.20, "sine", None),
                (0.34, 0.30, 1_500, 0.26, "sine", 2_400),
                (0.70, 0.12, 2_400, 0.25, "sine", None),
                (0.85, 0.11, 1_200, 0.23, "sine", None),
                (1.00, 0.11, 2_400, 0.23, "sine", None),
                (1.16, 0.25, 2_100, 0.18, "sine", 1_050),
                (1.52, 0.22, 1_900, 0.18, "sine", 2_700),
                (1.82, 0.25, 2_100, 0.15, "sine", None),
            ],
            "noise": [(1.48, 0.18, 0.06)],
        },
        2: {
            "duration": 1.75,
            "tones": [
                (0.00, 0.08, 440, 0.22, "sine", None),
                (0.10, 0.20, 1_800, 0.25, "sine", 2_600),
                (0.34, 0.07, 1_200, 0.24, "sine", None),
                (0.43, 0.07, 2_400, 0.24, "sine", None),
                (0.52, 0.07, 1_200, 0.23, "sine", None),
                (0.61, 0.07, 2_400, 0.23, "sine", None),
                (0.72, 0.28, 2_250, 0.22, "sine", 1_100),
                (1.08, 0.12, 3_000, 0.18, "sine", None),
                (1.24, 0.25, 2_050, 0.16, "sine", None),
            ],
            "noise": [(0.82, 0.30, 0.08)],
        },
        3: {
            "duration": 2.90,
            "tones": [
                (0.00, 0.15, 350, 0.20, "sine", None),
                (0.00, 0.15, 440, 0.16, "sine", None),
                (0.20, 0.35, 1_050, 0.22, "sine", 2_100),
                (0.66, 0.20, 1_100, 0.18, "sine", None),
                (0.91, 0.20, 2_200, 0.18, "sine", None),
                (1.16, 0.20, 1_100, 0.18, "sine", None),
                (1.43, 0.42, 1_950, 0.16, "sine", 1_000),
                (2.00, 0.13, 1_650, 0.18, "sine", None),
                (2.18, 0.13, 2_500, 0.16, "sine", None),
                (2.38, 0.30, 2_100, 0.14, "sine", None),
            ],
            "noise": [(0.56, 0.72, 0.10), (1.94, 0.43, 0.07)],
        },
        4: {
            "duration": 2.35,
            "tones": [
                (0.00, 0.10, 480, 0.22, "sine", None),
                (0.14, 0.38, 2_800, 0.24, "sine", 1_300),
                (0.58, 0.08, 1_600, 0.22, "sine", None),
                (0.69, 0.08, 2_900, 0.22, "sine", None),
                (0.80, 0.08, 1_600, 0.22, "sine", None),
                (0.91, 0.08, 2_900, 0.22, "sine", None),
                (1.05, 0.32, 1_250, 0.20, "sine", 2_500),
                (1.45, 0.11, 3_300, 0.17, "sine", None),
                (1.60, 0.11, 2_700, 0.17, "sine", None),
                (1.78, 0.34, 2_100, 0.16, "sine", None),
            ],
            "noise": [(1.25, 0.20, 0.05)],
        },
        5: {
            "duration": 1.35,
            "tones": [
                (0.00, 0.08, 410, 0.22, "sine", None),
                (0.11, 0.22, 1_600, 0.25, "sine", 2_400),
                (0.38, 0.09, 1_200, 0.23, "sine", None),
                (0.50, 0.09, 2_400, 0.23, "sine", None),
                (0.62, 0.09, 1_200, 0.22, "sine", None),
                (0.76, 0.25, 2_100, 0.18, "sine", 1_050),
                (1.08, 0.19, 2_700, 0.14, "sine", None),
            ],
            "noise": [],
        },
    }[version]
    buffer = [0.0] * int(configurations["duration"] * SAMPLE_RATE)
    for tone in configurations["tones"]:
        add_tone(buffer, *tone)
    for start, duration, amplitude in configurations["noise"]:
        add_noise(buffer, start, duration, amplitude)
    return buffer


def chiptune_curtain() -> list[float]:
    duration = 4.05
    buffer = [0.0] * int(duration * SAMPLE_RATE)
    beat = 0.20
    melody = [
        (0, 523.25), (1, 659.25), (2, 783.99), (3, 1_046.50),
        (4, 783.99), (5, 659.25), (6, 587.33), (7, 523.25),
        (8, 698.46), (9, 880.00), (10, 1_046.50), (11, 1_396.91),
        (12, 1_046.50), (13, 880.00), (14, 783.99), (15, 659.25),
        (16, 523.25), (18, 659.25), (20, 783.99), (22, 1_046.50),
        (24, 1_174.66), (26, 1_046.50), (28, 783.99), (30, 523.25),
    ]
    for step, frequency in melody:
        add_tone(buffer, step * beat / 2, beat * 0.88, frequency, 0.22, "square")

    bass = [130.81, 164.81, 196.00, 220.00, 174.61, 220.00, 261.63, 196.00]
    for step in range(32):
        frequency = bass[(step // 4) % len(bass)]
        add_tone(buffer, step * beat / 2, beat * 0.42, frequency, 0.12, "triangle")

    # Small noise bursts provide an 8-bit percussion accent without using samples.
    for step in range(0, 32, 4):
        add_noise(buffer, step * beat / 2, 0.035, 0.07)

    # A short final stinger makes the curtain feel complete.
    add_tone(buffer, 3.45, 0.42, 1_046.50, 0.20, "square", end_frequency=1_569.00)
    add_tone(buffer, 3.45, 0.42, 261.63, 0.11, "triangle")
    return buffer


def main() -> None:
    random.seed(20260902)
    output_dir = Path(__file__).resolve().parents[2] / "assets" / "audio"
    output_dir.mkdir(parents=True, exist_ok=True)
    original_modem = output_dir / "modem_section_transition.wav"
    original_chiptune = output_dir / "retro_chiptune_curtain.wav"
    if not original_modem.exists():
        write_wav(original_modem, modem_transition())
    for version in range(1, 6):
        write_wav(
            output_dir / f"modem_section_transition_v{version}.wav",
            modem_variant(version),
        )
    if not original_chiptune.exists():
        write_wav(original_chiptune, chiptune_curtain())
    print(f"Created WAV assets in {output_dir}")


if __name__ == "__main__":
    main()
