"""Synthesises the frying pan's strike sounds by modal synthesis (a struck metal plate rings at a few inharmonic
modes, each decaying on its own; a short filtered noise burst is the contact): a quick, lighter clank and a heavy,
lower, longer bong, three takes each. Stand-ins until recorded Freesound takes replace them.
Run: python3 tools/audio/make_pan_hits.py   (writes assets/audio/sfx/items/frying_pan/pan_*.wav)
"""
import os
import wave

import numpy as np

OUT = "assets/audio/sfx/items/frying_pan"
RATE = 44100
## A 24 cm steel pan's ringing modes (Hz, ratios of a circular plate's first modes) and their decay times (s).
MODES = [(1.0, 0.55), (2.29, 0.42), (3.6, 0.30), (5.4, 0.22), (7.1, 0.16), (9.3, 0.11)]


def strike(base_hz, length_s, gain, contact, seed):
	rng = np.random.default_rng(seed)
	t = np.arange(int(RATE * length_s)) / RATE
	out = np.zeros_like(t)
	for k, (ratio, decay) in enumerate(MODES):
		f = base_hz * ratio * (1.0 + rng.uniform(-0.012, 0.012))
		amp = (0.9 ** k) * rng.uniform(0.8, 1.1)
		out += amp * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / (decay * length_s / 0.9))
	## The contact: a few milliseconds of noise, low-passed by a running mean, louder for a heavy blow.
	noise = rng.normal(0.0, 1.0, int(RATE * 0.012))
	noise = np.convolve(noise, np.ones(6) / 6, mode="same") * np.exp(-np.arange(noise.size) / (RATE * 0.003))
	out[: noise.size] += contact * noise
	## A soft attack (no click) and a fade to silence.
	out *= np.minimum(1.0, t / 0.002)
	out *= np.minimum(1.0, (t[-1] - t) / 0.05)
	return gain * out / np.max(np.abs(out))


def write(name, samples):
	data = (np.clip(samples, -1.0, 1.0) * 32767).astype(np.int16)
	with wave.open(os.path.join(OUT, name), "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(RATE)
		w.writeframes(data.tobytes())


if __name__ == "__main__":
	os.makedirs(OUT, exist_ok=True)
	for i in range(3):
		write("pan_hit_quick_%d.wav" % (i + 1), strike(410.0 + 25 * i, 0.55, 0.7, 1.6, 10 + i))
		write("pan_hit_heavy_%d.wav" % (i + 1), strike(285.0 + 18 * i, 1.3, 0.95, 3.0, 20 + i))
	print("pan hits written to", OUT)
