"""Synthesises Henry's snow footstep banks.

Snow under a boot is thousands of tiny crushing events. The model follows two
open papers: Fontana & Bresin 2003 (crumpling: transients with power-law
energies arriving as a stochastic process) and Cook 2002 (PhISEM / "Modeling
Bill's Gait": particles exciting resonances under a heel-roll-toe force
envelope). Each surface is a preset of grain rate, band, decay and energy law,
plus the low "whump" of snow compressing and, where it belongs, the knock of
frozen ground, crust fractures, a leg swish or stick-slip squeak.

Writes mono 44.1 kHz 16-bit WAVs to assets/audio/sfx/footsteps/snow/ and one
SoundEvent bank per surface to data/audio/footsteps/. Run from the repo root:

    python tools/audio/generate_snow_footsteps.py

Needs numpy and soundfile. Deterministic: the same seeds give the same files.
"""
import glob
import math
import os

import numpy as np
import soundfile as sf

RATE = 44100
WAV_DIR = "assets/audio/sfx/footsteps/snow"
TRES_DIR = "data/audio/footsteps"
VARIANTS = 10
# Banks that now play the owner's recorded footsteps (assets/audio/sfx/player/snow_footsteps/,
# random of 8); this script no longer renders or writes them, only the layers below.
RECORDED = {"snow_thin", "snow_crust", "snow_step", "snow_wet", "snow_deep"}

# Surface presets. Times in seconds, frequencies in Hz.
#   heel/toe: force humps (start, width, weight); grains: crushing events;
#   body: low compression whump; knock: ground under snow; crack: crust breaks;
#   swish: leg ploughing; tail_s: file length.
PRESETS = {
    # A skin of snow over frozen ground: a short crunch on a hard knock.
    "snow_thin": dict(
        heel=(0.0, 0.035, 1.0), toe=(0.10, 0.05, 0.7),
        grains=dict(rate=1400, band=(1600, 5500), decay=(0.0004, 0.001), law=1.9, gain=0.7),
        body=dict(band=(120, 260), gain=0.15, width=0.08),
        knock=dict(freqs=(190, 310, 470), decay=0.018, gain=0.7),
        tail_s=0.32, volume_db=-10.0),
    # Wind crust: the slab snaps in a few loud fractures, then the powder under it.
    "snow_crust": dict(
        heel=(0.0, 0.04, 1.0), toe=(0.13, 0.06, 0.6),
        grains=dict(rate=700, band=(2000, 6500), decay=(0.0004, 0.001), law=2.0, gain=0.45),
        crack=dict(count=(3, 7), window=0.02, band=(1100, 3800), decay=(0.002, 0.006), gain=1.0),
        body=dict(band=(90, 200), gain=0.35, width=0.12),
        tail_s=0.4, volume_db=-9.0),
    # Dry snow a few inches deep: a dense fine crunch that rolls heel to toe.
    "snow_step": dict(
        heel=(0.0, 0.07, 1.0), toe=(0.15, 0.08, 0.8),
        grains=dict(rate=2400, band=(1300, 5000), decay=(0.0004, 0.001), law=2.1, gain=0.8),
        body=dict(band=(100, 240), gain=0.45, width=0.15),
        tail_s=0.42, volume_db=-9.0),
    # Wet snow near melting: fewer, lower, softer grains and a slushy squelch.
    "snow_wet": dict(
        heel=(0.0, 0.08, 1.0), toe=(0.16, 0.08, 0.7),
        grains=dict(rate=900, band=(700, 2400), decay=(0.0015, 0.004), law=2.3, gain=0.7),
        slush=dict(cutoff=1500, gain=0.35),
        body=dict(band=(90, 220), gain=0.45, width=0.16),
        tail_s=0.42, volume_db=-9.0),
    # Knee-deep powder: the leg swishes in, the boot sinks for a long muffled whump.
    "snow_deep": dict(
        heel=(0.01, 0.16, 1.0), toe=(0.22, 0.14, 0.6),
        grains=dict(rate=1600, band=(350, 1400), decay=(0.0015, 0.003), law=2.0, gain=0.3),
        body=dict(band=(50, 140), gain=1.0, width=0.28),
        swish=dict(band=(250, 800), attack=0.025, length=0.16, gain=0.3),
        tail_s=0.62, volume_db=-8.0),
    # Dry snow below about -10 °C: crystals crush and stick-slip into squeaks.
    "snow_squeak": dict(
        heel=(0.0, 0.06, 1.0), toe=(0.12, 0.06, 0.8),
        squeak=dict(count=(2, 5), length=(0.02, 0.05), freq=(700, 1500), glide=0.22, gain=1.0),
        grains=dict(rate=500, band=(3000, 8000), decay=(0.0003, 0.0007), law=2.0, gain=0.25),
        tail_s=0.3, volume_db=-8.0),
    # A boot pulled out of a deep print: a slow rising suck and crumbs falling back.
    "snow_pull": dict(
        heel=(0.0, 0.22, 1.0), toe=(0.18, 0.1, 0.5),
        grains=dict(rate=500, band=(900, 3000), decay=(0.001, 0.003), law=1.8, gain=0.5),
        body=dict(band=(60, 170), gain=0.6, width=0.25),
        swish=dict(band=(250, 900), attack=0.12, length=0.22, gain=0.5),
        tail_s=0.55, volume_db=-12.0),
}


def envelope(t, preset, rng):
    """Force on the ground over the step: a heel hump and a toe hump."""
    env = np.zeros_like(t)
    for key in ("heel", "toe"):
        start, width, weight = preset[key]
        start *= rng.uniform(0.85, 1.15)
        width *= rng.uniform(0.85, 1.15)
        x = (t - start) / width
        hump = np.where(x > 0, x * np.exp(1.0 - x), 0.0)
        env += weight * rng.uniform(0.8, 1.1) * hump
    return env / max(env.max(), 1e-9)


def power_law(rng, n, law):
    """Energies with a power-law tail, as crumpling transients have."""
    u = rng.uniform(1e-3, 1.0, n)
    return np.minimum(u ** (-1.0 / (law - 1.0)), 60.0) / 60.0


def grains(t, env, spec, rng):
    """Crushing events: a Poisson stream shaped by force, each a damped ping."""
    out = np.zeros_like(t)
    rate = spec["rate"] * rng.uniform(0.8, 1.2)
    dt = 1.0 / RATE
    # Arrivals follow the envelope (thinning of a homogeneous process).
    count = rng.poisson(rate * t[-1])
    times = np.sort(rng.uniform(0, t[-1], count))
    keep = rng.uniform(0, 1, count) < np.interp(times, t, env)
    times = times[keep]
    amps = power_law(rng, len(times), spec["law"])
    lo, hi = spec["band"]
    for when, amp in zip(times, amps):
        freq = math.exp(rng.uniform(math.log(lo), math.log(hi)))
        tau = rng.uniform(*spec["decay"])
        i0 = int(when / dt)
        n = min(int(tau * 6 / dt) + 1, len(t) - i0)
        if n <= 1:
            continue
        k = np.arange(n) * dt
        out[i0:i0 + n] += amp * np.exp(-k / tau) * np.sin(2 * math.pi * freq * k + rng.uniform(0, 6.28))
    return out * spec["gain"]


def band_noise(n, lo, hi, rng):
    """White noise band-passed by FFT masking."""
    spectrum = np.fft.rfft(rng.normal(0, 1, n))
    freqs = np.fft.rfftfreq(n, 1.0 / RATE)
    mask = np.clip((freqs - lo * 0.7) / (lo * 0.3 + 1e-9), 0, 1) * np.clip((hi * 1.3 - freqs) / (hi * 0.3), 0, 1)
    y = np.fft.irfft(spectrum * mask, n)
    return y / max(np.abs(y).max(), 1e-9)


def body(t, env, spec, rng):
    """Low whump of a snow column compressing under the boot."""
    lo, hi = spec["band"]
    noise = band_noise(len(t), lo, hi, rng)
    x = t / (spec["width"] * rng.uniform(0.85, 1.15))
    shape = np.where(x > 0, x * np.exp(1 - x), 0.0)
    return noise * shape * (0.5 + 0.5 * env) * spec["gain"]


def knock(t, spec, rng):
    """Boot on frozen ground under a thin skin of snow."""
    out = np.zeros_like(t)
    for freq in spec["freqs"]:
        f = freq * rng.uniform(0.9, 1.1)
        out += np.exp(-t / spec["decay"]) * np.sin(2 * math.pi * f * t) * rng.uniform(0.5, 1.0)
    click = band_noise(len(t), 800, 4000, rng) * np.exp(-t / 0.003)
    return (out / len(spec["freqs"]) + 0.4 * click) * spec["gain"]


def cracks(t, spec, rng):
    """Crust slab fractures at heel strike: a few loud, longer transients."""
    out = np.zeros_like(t)
    dt = 1.0 / RATE
    for _ in range(rng.integers(spec["count"][0], spec["count"][1] + 1)):
        when = rng.uniform(0, spec["window"])
        i0 = int(when / dt)
        tau = rng.uniform(*spec["decay"])
        n = min(int(tau * 6 / dt), len(t) - i0)
        k = np.arange(n) * dt
        burst = band_noise(n, *spec["band"], rng) if n > 64 else np.zeros(n)
        out[i0:i0 + n] += rng.uniform(0.5, 1.0) * burst * np.exp(-k / tau)
    return out * spec["gain"]


def swish(t, spec, rng):
    """Leg ploughing through snow before the boot lands."""
    noise = band_noise(len(t), *spec["band"], rng)
    attack = spec["attack"] * rng.uniform(0.8, 1.2)
    length = spec["length"] * rng.uniform(0.8, 1.2)
    shape = np.clip(t / attack, 0, 1) * np.clip((length - t) / (length * 0.5), 0, 1)
    return noise * shape * spec["gain"]


def slush(t, env, spec, rng):
    noise = band_noise(len(t), 150, spec["cutoff"], rng)
    return noise * env * spec["gain"]


def squeaks(t, spec, rng):
    """Stick-slip chirps: short tones gliding up, roughened at the slip rate."""
    out = np.zeros_like(t)
    dt = 1.0 / RATE
    start = 0.0
    for _ in range(rng.integers(spec["count"][0], spec["count"][1] + 1)):
        length = rng.uniform(*spec["length"])
        start += rng.uniform(0.005, 0.03)
        i0 = int(start / dt)
        n = min(int(length / dt), len(t) - i0)
        if n <= 32:
            break
        k = np.arange(n) * dt
        f0 = rng.uniform(*spec["freq"])
        freq = f0 * (1 + spec["glide"] * k / length)
        phase = 2 * math.pi * np.cumsum(freq) * dt
        rough = 0.6 + 0.4 * np.sign(np.sin(2 * math.pi * rng.uniform(60, 130) * k))
        shape = np.sin(math.pi * k / length) ** 0.7
        out[i0:i0 + n] += shape * rough * (np.sin(phase) + 0.3 * np.sin(2 * phase)) * rng.uniform(0.6, 1.0)
        start += length
    return out * spec["gain"]


def finish(x):
    """High-pass the rumble, fade the tail, RMS-normalise with a peak ceiling."""
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / RATE)
    spectrum *= np.clip((freqs - 30) / 20, 0, 1)
    y = np.fft.irfft(spectrum, len(x))
    fade = int(RATE * 0.03)
    y[-fade:] *= np.linspace(1, 0, fade) ** 2
    y[: int(RATE * 0.001)] *= np.linspace(0, 1, int(RATE * 0.001))
    rms = math.sqrt(float(np.mean(y ** 2))) + 1e-12
    y *= 10 ** (-18 / 20) / rms
    peak = np.abs(y).max()
    if peak > 10 ** (-1 / 20):
        y *= 10 ** (-1 / 20) / peak
    return y


def render(name, preset, seed):
    rng = np.random.default_rng(seed)
    t = np.arange(int(preset["tail_s"] * RATE)) / RATE
    env = envelope(t, preset, rng)
    x = np.zeros_like(t)
    if "grains" in preset:
        x += grains(t, env, preset["grains"], rng)
    if "body" in preset:
        x += body(t, env, preset["body"], rng)
    if "knock" in preset:
        x += knock(t, preset["knock"], rng)
    if "crack" in preset:
        x += cracks(t, preset["crack"], rng)
    if "swish" in preset:
        x += swish(t, preset["swish"], rng)
    if "slush" in preset:
        x += slush(t, env, preset["slush"], rng)
    if "squeak" in preset:
        x += squeaks(t, preset["squeak"], rng)
    return finish(x)


def write_bank(name, preset, files):
    lines = ['[gd_resource type="Resource" script_class="SoundEvent" load_steps=%d format=3]' % (len(files) + 2), "",
             '[ext_resource type="Script" path="res://core/audio/sound_event.gd" id="1_event"]']
    ids = []
    for i, path in enumerate(files, 1):
        rid = "%d_%s" % (i + 1, os.path.splitext(os.path.basename(path))[0])
        ids.append(rid)
        lines.append('[ext_resource type="AudioStream" path="res://%s" id="%s"]' % (path.replace("\\", "/"), rid))
    lines += ["", "[resource]", 'script = ExtResource("1_event")',
              "streams = Array[AudioStream]([%s])" % ", ".join('ExtResource("%s")' % r for r in ids),
              "pick = 0", 'bus = &"SFX"', "volume_db = %.1f" % preset["volume_db"], "volume_jitter_db = 1.5",
              "pitch = 1.0", "pitch_jitter = 0.050", "spatial = true", "unit_size = 3.0",
              "max_distance_m = 25.0", "max_instances = 4", "cooldown_s = 0.0", ""]
    with open(os.path.join(TRES_DIR, name + ".tres"), "w", encoding="utf8", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    os.makedirs(WAV_DIR, exist_ok=True)
    os.makedirs(TRES_DIR, exist_ok=True)
    for old in glob.glob(os.path.join(WAV_DIR, "*.wav")):
        os.remove(old)
        if os.path.exists(old + ".import"):
            os.remove(old + ".import")
    for index, (name, preset) in enumerate(PRESETS.items()):
        if name in RECORDED:
            continue
        files = []
        for v in range(VARIANTS):
            path = os.path.join(WAV_DIR, "%s_%02d.wav" % (name, v + 1))
            sf.write(path, render(name, preset, 1000 * index + v), RATE, subtype="PCM_16")
            files.append(path)
        write_bank(name, preset, files)
        print(name, len(files))


if __name__ == "__main__":
    main()
