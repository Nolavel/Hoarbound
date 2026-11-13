"""Synthesises placeholder thin-ice sounds until real recordings replace them.

A crack is a dispersive chirp: high frequencies arrive first as a flexural
wave runs through floating ice, so the pitch falls ("pew"). The creak is a
low groan driven by stick-slip pulses. Deterministic: fixed seeds.
Run: python3 tools/audio/synth_ice_sfx.py
"""
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "assets/audio/sfx/environment/ice"


def write(name: str, signal: np.ndarray) -> None:
    peak = np.max(np.abs(signal)) or 1.0
    data = (signal / peak * 0.89 * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / name), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data.tobytes())


def lowpass(signal: np.ndarray, cutoff_hz: float) -> np.ndarray:
    alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff_hz / RATE)
    out = np.empty_like(signal)
    acc = 0.0
    for i, value in enumerate(signal):
        acc += alpha * (value - acc)
        out[i] = acc
    return out


def crack(seed: int, length_s: float, f_high: float, f_low: float, tau: float) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = np.arange(int(length_s * RATE)) / RATE
    freq = f_low + (f_high - f_low) * np.exp(-t / tau)
    phase = 2.0 * np.pi * np.cumsum(freq) / RATE
    chirp = np.sin(phase) * np.exp(-t / (length_s * 0.35))
    click = rng.normal(0.0, 1.0, t.size) * np.exp(-t / 0.004)
    tail = lowpass(rng.normal(0.0, 1.0, t.size), 900.0) * np.exp(-t / (length_s * 0.4)) * 0.6
    return chirp + 0.7 * click + tail


def creak_loop(seed: int, length_s: float) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(length_s * RATE)
    t = np.arange(n) / RATE
    f0 = 82.0 + 14.0 * np.sin(2.0 * np.pi * t / length_s)
    phase = 2.0 * np.pi * np.cumsum(f0) / RATE
    tone = sum(np.sin(k * phase) / k for k in range(1, 7))
    pulses = np.zeros(n)
    position = 0.0
    while position < length_s:
        index = int(position * RATE)
        pulses[index : index + 60] += np.hanning(60)[: min(60, n - index)]
        position += 1.0 / rng.uniform(16.0, 28.0)
    envelope = lowpass(pulses, 40.0)
    swell = 0.55 + 0.45 * np.sin(np.pi * t / length_s) ** 2
    signal = tone * (0.35 + envelope * 6.0) * swell
    fade = int(0.05 * RATE)
    signal[:fade] = signal[:fade] * np.linspace(0, 1, fade) + signal[-fade:] * np.linspace(1, 0, fade)
    return signal[: n - fade]


def splash_break(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    length_s = 2.2
    t = np.arange(int(length_s * RATE)) / RATE
    signal = np.zeros(t.size)
    big = crack(seed + 1, 0.6, 7000.0, 180.0, 0.05)
    signal[: big.size] += big * 1.4
    for _ in range(14):
        start = int(rng.uniform(0.0, 0.35) * RATE)
        grain = crack(int(rng.integers(1 << 30)), 0.12, rng.uniform(3000, 6000), rng.uniform(300, 700), 0.02)
        end = min(t.size, start + grain.size)
        signal[start:end] += grain[: end - start] * rng.uniform(0.2, 0.5)
    wash = lowpass(rng.normal(0.0, 1.0, t.size), 1400.0)
    wash *= np.clip((t - 0.12) / 0.05, 0.0, 1.0) * np.exp(-np.clip(t - 0.17, 0.0, None) / 0.5)
    signal += wash * 1.6
    for _ in range(22):
        start = rng.uniform(0.25, 1.9)
        dur = rng.uniform(0.03, 0.07)
        bt = np.arange(int(dur * RATE)) / RATE
        f = rng.uniform(400, 1100) * (1.0 + bt / dur * 1.5)
        bubble = np.sin(2.0 * np.pi * np.cumsum(f) / RATE) * np.exp(-bt / (dur * 0.4))
        i = int(start * RATE)
        end = min(t.size, i + bubble.size)
        signal[i:end] += bubble[: end - i] * rng.uniform(0.1, 0.25)
    return signal


def main() -> None:
    write("ice_crack_1.wav", crack(11, 0.45, 5200.0, 260.0, 0.030))
    write("ice_crack_2.wav", crack(23, 0.55, 6400.0, 320.0, 0.045))
    write("ice_crack_3.wav", crack(37, 0.35, 4300.0, 210.0, 0.022))
    write("ice_creak_loop.wav", creak_loop(5, 2.4))
    write("ice_break_splash.wav", splash_break(91))


if __name__ == "__main__":
    main()
