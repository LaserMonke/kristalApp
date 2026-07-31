"""Synthesise the OptionsSchool intro chime from scratch.

An original composition: a low thump, then two plucked tones a perfect fifth
apart (A3 -> E4), each with harmonics and an exponential decay, plus a quiet
delayed copy for a sense of space. Nothing sampled, nothing borrowed.
"""
import math
import struct
import wave

RATE = 44100
DURATION = 1.6
PEAK = 0.82


def envelope(t, start, attack, decay):
    """Fast attack, exponential decay. Silent before `start`."""
    if t < start:
        return 0.0
    dt = t - start
    if dt < attack:
        return dt / attack
    return math.exp(-(dt - attack) / decay)


def tone(t, start, freq, decay, harmonics):
    env = envelope(t, start, 0.006, decay)
    if env <= 0.0:
        return 0.0
    dt = t - start
    value = 0.0
    for n, weight in enumerate(harmonics, start=1):
        value += weight * math.sin(2 * math.pi * freq * n * dt)
    return value * env


def sample(t):
    v = 0.0
    # Low thump under the first note — felt more than heard.
    v += 0.55 * tone(t, 0.00, 110.0, 0.13, (1.0, 0.18))
    # A3, then E4 a fifth above it.
    v += 0.60 * tone(t, 0.02, 220.0, 0.42, (1.0, 0.42, 0.16, 0.06))
    v += 0.55 * tone(t, 0.38, 330.0, 0.62, (1.0, 0.36, 0.14, 0.05))
    # A quiet, slightly detuned copy trailing behind, for air.
    v += 0.16 * tone(t, 0.44, 331.4, 0.75, (1.0, 0.22))
    return v


def main():
    frames = int(RATE * DURATION)
    raw = [sample(i / RATE) for i in range(frames)]

    peak = max(abs(x) for x in raw) or 1.0
    scale = PEAK / peak

    # Fade the last 120ms to zero so the file never ends on a click.
    fade = int(RATE * 0.12)
    out = bytearray()
    for i, x in enumerate(raw):
        v = x * scale
        if i > frames - fade:
            v *= (frames - i) / fade
        out += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))

    with wave.open("assets/audio/intro_chime.wav", "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(bytes(out))
    print(f"wrote {frames} frames ({DURATION}s)")


if __name__ == "__main__":
    main()
