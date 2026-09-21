# Benchmarks

Read when measuring a model, or before quoting a number one of these produced.

The prompts and the scoring rules live here because they are a contract rather
than a measurement: they have to stay fixed for numbers taken months apart on
two different machines to mean anything. The numbers themselves belong to the
machine that produced them, in
[`hardware-24gb-blackwell.md`](./hardware-24gb-blackwell.md) or
[`hardware-16gb-ada.md`](./hardware-16gb-ada.md). The harness is scratch and
gets rewritten per session; this file is the durable half.

Seeds are **42, 777 and 1337** everywhere. Three of them, because a single seed
cannot separate an effect from sampling noise, and a step-count claim once
shipped from this repository on the strength of one image.

## Schedule-sensitive set

Re-run for every step, resolution or sampling-shift decision.

| #  | Prompt                                                                                                        |
| -- | ------------------------------------------------------------------------------------------------------------- |
| S1 | `A neon shop sign that reads "QWEN IMAGE 2.1", rainy night, reflections on wet pavement`                      |
| S2 | `A close-up of a barn owl's face, individual feather barbs visible, shallow depth of field, natural light`    |
| S3 | `A studio portrait of an elderly woman with deeply lined skin, soft key light from the left, dark background` |

S1 is Qwen's own reference prompt, so glyph fidelity is measured against what
the vendor shows. S2 keeps the feather-barb yardstick the FLUX.2 print
measurements already use, so the two model families stay comparable.

All three are deliberately photographic and single-subject. Acuity is only
legible on high-frequency detail, which makes this set right for choosing a step
count and **wrong for judging a model overall**.

## Characterization set

Runs once per model, not per configuration: prompt adherence barely moves with
step count, so repeating it per sweep would burn hours to re-measure a constant.

| #  | Prompt                                                                                                                                   | Tests               |
| -- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------- |
| C1 | `a photo of three sports balls`                                                                                                          | counting            |
| C2 | `a photo of a dog right of a teddy bear`                                                                                                 | spatial relation    |
| C3 | `a photo of a purple wine glass and a black apple`                                                                                       | attribute binding   |
| C4 | `a photo of a fork and a knife`                                                                                                          | two-object          |
| C5 | `This is an RGBA image with transparency. A cute cartoon dragon sticker. The image has alpha channel and the background is transparent.` | transparency        |
| C6 | `A modernist concrete staircase in hard midday sunlight, sharp geometric shadows, straight railings, wide angle`                         | hard edges          |
| C7 | `A flat vector illustration of a fox in a forest, bold shapes, limited palette, no gradients`                                            | non-photoreal style |
| C8 | `A wide mountain valley at dawn, layered ridgelines receding into haze`                                                                  | depth               |
| C9 | `A red paper lantern with the characters "欢迎光临" in gold, night market background`                                                        | non-Latin script    |

C1 to C4 are verbatim lines from GenEval's `evaluation_metadata.jsonl` (MIT, 553
prompts). C5 is Qwen's published RGBA example. C6 to C9 exist because every
GenEval line is `a photo of X`, which leaves style, geometry, depth and non-Latin
script completely untested.

## Scoring

**MAD**, mean absolute difference on RGB in 0-255, answers one question: did this
parameter change the image. It is reliable for that and for nothing else.

**Laplacian variance** is reported for continuity with older tables but never
decides anything. It rewards high-frequency energy, so grain and sharpening
artifacts score the same as real detail.

**Convergence is how a step count gets decided.** Render a high-step reference,
then measure MAD from each candidate to it. Whichever sits closer is the more
converged schedule. This replaces "which looks sharper", which neither MAD nor
Laplacian variance can answer, with a question they can.

**Adherence scoring is by eye.** Real GenEval runs a Mask2Former detector; that
would drag `mmdet` into a workflow-tuning repository for a set of prompts run
once. The consequence has to be stated wherever the numbers appear: **results
from C1 to C9 are not comparable to published GenEval scores.**

**Text legibility is also by eye.** No OCR is installed and none of
`pytesseract`, `easyocr`, `rapidocr`, `paddleocr` or a `tesseract` binary is
present. At nine renders per configuration, reading nine signs is more reliable
than OCR on stylised neon anyway.

## Timing

Server-side only, `execution_start` to `execution_success` from
`GET /history/{id}`, never client wall clock.
[`http-api.md`](./http-api.md) → *Timing a run*.

Record the cached node count on every run. A fully cached run measures nothing,
and absolute times are comparable only between runs at the same cache state.

Renders on the Blackwell box are bit-identical across server restarts at a
matched seed, measured at MAD 0.000, so any non-zero difference in these tables
is a real effect rather than jitter.
