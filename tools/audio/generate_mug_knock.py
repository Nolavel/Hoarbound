"""Synthesises the dull knock of the enamel mug hanging on the pack against the tool handles.

Modal synthesis after van den Doel & Pai (1998, "The sounds of physical shapes") and van den Doel,
Kry & Pai (2001, "FoleyAutomatic"): an impact is a contact force pulse driving a few exponentially
damped modes. What makes it dull rather than a clink: a soft contact (a plastic and rubber handle on
enamel, a 0.4-0.7 ms half-sine force) that filters the high modes, the handle's own heavily damped
low thump, the mug body's mid "bonk", and an enamel ring that dies within tens of milliseconds.

Writes mono 44.1 kHz 16-bit WAVs to assets/audio/sfx/backpack/ and the SoundEvent bank
data/audio/backpack/mug_knock.tres. Run from the repo root:

    python tools/audio/generate_mug_knock.py

Needs numpy and soundfile. Deterministic: the same seeds give the same files.
"""
import os

import numpy as np
import soundfile as sf

RATE = 44100
WAV_DIR = "assets/audio/sfx/backpack"
TRES = "data/audio/backpack/mug_knock.tres"
VARIANTS = 5
LENGTH_S = 0.32
## Modes: frequency (Hz), decay time to 1/e (s), amplitude. Handle thump, body bonk, enamel ring.
MODES = [(185.0, 0.016, 0.75), (310.0, 0.022, 0.45), (540.0, 0.034, 0.55), (880.0, 0.03, 0.22),
	(1390.0, 0.05, 0.3), (2240.0, 0.035, 0.2), (3480.0, 0.022, 0.12)]


def knock(seed: int) -> np.ndarray:
	rng = np.random.default_rng(seed)
	n = int(RATE * LENGTH_S)
	t = np.arange(n) / RATE
	response = np.zeros(n)
	for freq, decay, amp in MODES:
		f = freq * rng.uniform(0.94, 1.06)
		d = decay * rng.uniform(0.85, 1.15)
		a = amp * rng.uniform(0.8, 1.2)
		response += a * np.exp(-t / d) * np.sin(2.0 * np.pi * f * t + rng.uniform(0.0, 0.4))
	## Soft contact: a half-sine force pulse; the longer it lasts, the duller the knock.
	contact = rng.uniform(0.0004, 0.0007)
	m = max(int(RATE * contact), 2)
	pulse = np.sin(np.pi * np.arange(m) / m)
	signal = np.convolve(response, pulse)[:n]
	## A brief scuff of the surfaces sliding as they meet: low-passed noise, a few milliseconds.
	scuff = rng.standard_normal(n) * np.exp(-t / 0.004) * 0.08
	kernel = np.ones(12) / 12.0
	signal += np.convolve(scuff, kernel, mode="same")
	## Fade the tail to silence and normalise to -4 dBFS peak.
	signal *= np.clip((LENGTH_S - t) / 0.04, 0.0, 1.0)
	return signal / np.max(np.abs(signal)) * 10 ** (-4.0 / 20.0)


def main() -> None:
	os.makedirs(WAV_DIR, exist_ok=True)
	os.makedirs(os.path.dirname(TRES), exist_ok=True)
	names = []
	for i in range(VARIANTS):
		name = "mug_knock_%02d.wav" % (i + 1)
		sf.write(os.path.join(WAV_DIR, name), knock(4100 + i * 37), RATE, subtype="PCM_16")
		names.append(name)
		print("mug knock: wrote %s/%s" % (WAV_DIR, name))
	lines = ['[gd_resource type="Resource" script_class="SoundEvent" load_steps=%d format=3]' % (len(names) + 2), "",
		'[ext_resource type="Script" path="res://core/audio/sound_event.gd" id="1_event"]']
	for i, name in enumerate(names):
		lines.append('[ext_resource type="AudioStream" path="res://%s/%s" id="%d_knock"]' % (WAV_DIR, name, i + 2))
	streams = ", ".join('ExtResource("%d_knock")' % (i + 2) for i in range(len(names)))
	lines += ["", "[resource]", 'script = ExtResource("1_event")', "streams = Array[AudioStream]([%s])" % streams,
		"pick = 0", 'bus = &"SFX"', "volume_db = -10.0", "volume_jitter_db = 2.0", "pitch = 1.0", "pitch_jitter = 0.06",
		"spatial = true", "unit_size = 2.0", "max_distance_m = 15.0", "max_instances = 3", "cooldown_s = 0.09", ""]
	with open(TRES, "w") as f:
		f.write("\n".join(lines))
	print("mug knock: wrote %s" % TRES)


if __name__ == "__main__":
	main()
