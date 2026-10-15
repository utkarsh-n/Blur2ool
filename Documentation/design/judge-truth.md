# Blur2ool: judge verdict, lens "Truth" (mathematical and technical honesty + pedagogy)

Date: 14 October 2026. Judge: lens = are the layers correct and genuinely illuminating; are claims about proprietary internals labeled INFERRED and measured where possible; does each blur's uniqueness come through via the right test image and plots; are misconceptions baked in.

Status: IN PROGRESS (written incrementally).

## 0. Method

(to fill)

### Interim notes (working; replaced by the final sections below when done)

- All three concepts read in full (Instrument 674 lines, Descent 958 lines, Engine 864 lines).
- Arithmetic spot-checked by hand so far, all correct: Gaussian half-amplitude 0.1874/σ, −3 dB 0.1325/σ, FWHM 2.3548σ, 10–90 % 2.563σ; box w = √(12σ²+1); tent σ² = r(r+2)/6; disc zeros 0.6098/R, 1.1166/R, min −0.1323 at 0.8174/R; hexagon area 2.598R², σ = 0.4564R; binomial n = 4σ²; Kawase {0,1,2,2,3} σ = √28.5 = 5.34; frosted-glass σ² = a(a+1)/3; bilateral 9.4 % vs 43.3 %, 0.581 vs 0.513; hexagon HDR energy 100/665.1 = 0.1504 → 108/255; step-edge probes 0.4500/179, 0.7065/219, 0.7137/220; zoom sampling N ≥ a·r_max + 1; thread/threadgroup indices.
- VERIFIED by `$TMPDIR/blur2ool-judge-truth/checks.py` and `nyquist2.py`: (a) explicit 5-point heat at λ = 0.25, 32 steps: PSF has exactly zero mass on odd-parity pixels (checkerboard-sparse PSF, σ exactly 4.0); a 1-px checkerboard is unchanged after 32 steps and inverted after 31. (b) σ_eff 3.9626 / 7.9098 / 11.8564 for σ 4 / 8 / 12 (all concepts right); ripple −0.00100 / −0.00115 / −0.00121 (right). (c) Linear-sampling offsets and weights in Descent and Engine exact. (d) Zoom, uniform-in-s weights: density along ln r varies 0.889–1.111 (a = 0.2 one-sided) and 0.950–1.050 (a = 0.1 centred): NOT an exact box; research §1.8 says so, concepts dropped the qualifier. (e) Three segments convolved → PSF max/mean 3.07 (pyramid-like, not flat); union of three rhombi → flat (CV 0.05). (f) Nyquist response at σ = 1: continuous 0.0072, sampled (k = 3) 0.0141, integrated 0.0092, Lindeberg 0.1353. All three concepts quote 0.72 % for the app's sampled kernel.
- Research cross-checks: CSS `blur()` gamma-space is REFERENCE (Filter Effects 1 §5 quote) — concepts right. SwiftUI `.nonLinear` gamma blend is MEASURED offscreen only; on-screen INFERRED (stack-semantics §3.1). Render tile size for ordinary render passes is not published (gpu-pipeline §1.2: UNVERIFIED); 32 × 32 is only the Apple9 maximum. `.shaderWrite` → no lossless compression before Apple10 is REFERENCE (Tech Talk 111431). `CALayer.shadowRadius`: three MEASURED research values disagree by ~2× (σ = r/2 vs 0.88–0.93 r vs 0.94–0.99 r); only Engine flags it.
- Suspected errors to verify: (1) explicit heat equation at λ = 1/4 (all three concepts' default) maps a 1-px checkerboard to its negative every step; (2) "zoom blur is an exact box in log-polar" holds only for geometric (log-uniform) spacing; (3) "MTF" used for a signed transfer function; "|H| with negative lobes" is self-contradictory; (4) kurtosis convention mixed (3.0 vs excess 0) inside Instrument; (5) render-tile 32×32 labelled COMPUTED in Engine; (6) hexagon spectrum described as "sinc²" in Descent §8.3; (7) CSS `blur()` colour space; SwiftUI default blend space; CI 191/133 cross-check σ; CALayer.shadowRadius conflict.

## 1. Scores at a glance

(to fill)

## 2. Concept "Instrument"

(to fill)

## 3. Concept "Descent"

(to fill)

## 4. Concept "Engine"

(to fill)

## 5. Cross-cutting technical errors and misconceptions found

(to fill)

## 6. Winner

(to fill)

## 7. Graft list (the final design must include)

(to fill)

## 8. Must avoid

(to fill)
