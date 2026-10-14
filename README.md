# GLM-5.3-Flash on six RX 6700 XT (RDNA2) with Project Maya

Getting [Project Maya](https://github.com/mw00/project-maya) to serve the 321B-parameter
GLM-5.3-Flash on AMD RDNA2 cards, which its HIP backend lists as "builds, not validated".
Result: **16 tokens/s single request, 19.5 tokens/s combined for parallel requests, 131K context**,
up from 1.6 tokens/s on the first working configuration.

Work done 2026-10-11 to 2026-10-13 by **Claude Opus 5.5** (Anthropic, model ID `claude-opus-5-5`)
running as an agent in Claude Code, directed by the repository owner. All numbers below were
measured on the machine described here; estimates are marked as such.

## Hardware and software

| | |
|---|---|
| GPUs | 6x AMD Radeon RX 6700 XT 12 GB (gfx1031). Two in slots (x8 and x4, PCIe Gen3), four on x1 risers (Gen2) |
| CPU / RAM | Ryzen 5 3400G (4 cores, AVX2, no AVX-512), 64 GB DDR4-2400 |
| Storage | SATA SSD (Samsung 850) and a 1 TB hard disk. No NVMe |
| OS / ROCm | Ubuntu 22.04, kernel 6.8, system ROCm with HIP 7.15 (ships gfx1031 kernels; no `HSA_OVERRIDE_GFX_VERSION` needed) |
| Engine | Project Maya v1.0.34, commit `bdd4167`, plus the patches in `patches/` |
| Models | Maya-S24 (94.7 GB); huihui-ai abliterated UD-IQ2_XXS (101.8 GB) |

## Results

Mean of three 500-token answers, greedy, thinking off.

| Configuration | Context | Answer speed | Notes |
|---|---|---|---|
| 2 GPUs, installer defaults | 8K | 1.6 tok/s | Disk-bound: 33-50 SSD reads per token |
| 2 GPUs, 1 GB VRAM reserve | 8K | 1.95 tok/s | |
| 6 GPUs | 8K | 2.9 tok/s | No disk reads; misses copied over x1 risers at ~18 ms each |
| 6 GPUs, RAM-tier experts on the CPU | 131K | 9.2 tok/s | `STRATA_GLM_PCIE_SHARE=0` |
| + VRAM reserve 384 MB | 131K | 10.1 tok/s | Exact answers |
| + trunk-keep map M1 | 131K | 12.0 tok/s | 97.1% same top token |
| + trunk-keep map P1, tuned | 131K | 14.5 tok/s | 95.6% same top token |
| + trunk-keep map M3, tuned | 131K | **16.0 tok/s** | 88.4% same top token |
| M3, 2-4 requests at once (`STRATA_GLM_SEQS=4`) | 131K | **19.5 tok/s combined** | |
| Abliterated UD-IQ2_XXS, exact | 131K | 8.6-8.8 tok/s | |
| Abliterated UD-IQ2_XXS, M3 | 131K | 14.4 tok/s | Map quality not scored on this model |

"Tuned" = 3 CPU-lane threads and `STRATA_GLM_MTP_KEEP=0`.

Other measurements:

- Prompt reading: ~35 tok/s for a 4.4K-token prompt, 105-112 tok/s for a 28K-token prompt.
- A new long prompt adds a one-off delay of roughly 10-15 s before answers reach full speed.
- A 28K-token prompt with a follow-up turn returned correct, grounded answers; the follow-up
  reused the cache and ran at 13.1 tok/s.
- Context cost is small: 131K reserves 1.93 GB across the six cards (0.34 GB at 8K).

### Trunk-keep quality (scored on this machine)

`STRATA_GLM_TRUNK_KEEP_MAP` skips the lowest-ranked experts that are not in VRAM, per layer.
Scored with the engine's `STRATA_GLM_SCORE` mode on 1,000 tokens (half prose, half Python) of
Maya-S24 against the unmodified model. Exact mode is bit-for-bit reproducible (KL 0 between runs).

| Map | Layers skipped in | KL | Same top token | Perplexity | CPU experts/token |
|---|---|---|---|---|---|
| exact | none | 0 | 100% | 6.338 | 41.5 |
| M1 | 23-44 | 0.006 | 97.1% | +0.3% | 30.8 |
| P1 | 23-44 | 0.017 | 95.6% | +0.5% | 25.2 |
| P4 | 23-44 | 0.021 | 93.7% | +0.3% | 24.2 |
| P2 | 17-44 | 0.032 | 91.0% | +1.1% | 23.0 |
| M2 | 10-44 | 0.045 | 90.4% | +1.0% | 22.7 |
| P3 | 10-44 | 0.056 | 89.8% | +3.5% | 20.0 |
| M3 | 10-44 | 0.068 | 88.4% | +2.4% | 18.0 |
| M4 | 3-44 | 0.117 | 83.4% | +6.7% | 8.4 |

Maps that leave layers 0-22 untouched stay above 93%. Map strings are in `scripts/use-map.sh`,
`scripts/score.py` and `scripts/score2.py`. With a map enabled, output at temperature 0 is not reproducible between
runs, because what is skipped depends on what is in VRAM at that moment.

## What made it work

1. **Build without rocWMMA on gfx10xx.** `glm_batch.cu` did not compile for gfx1031: RDNA2 has
   no WMMA instructions and rocWMMA static-asserts. The patch leaves that kernel out and uses the
   engine's existing F32 prompt-attention kernel.
2. **All six cards.** The engine supports up to 16 GPUs; only the HIP installer check limited AMD
   to two. With six, VRAM plus RAM hold every expert and decode makes no disk reads.
3. **Misses computed on the CPU, not copied over the risers.** The engine measured 17.8 ms to
   copy one expert to a riser card against 0.6-0.9 ms to compute it on the CPU, but did not use
   the CPU lane at all in six-card mode until `STRATA_GLM_CPU_LANE` was set.
4. **Smaller VRAM reserve, late-layer skipping, cheaper draft guesses.**

Remaining limit: a fixed ~70 ms per token independent of misses (about 20 tok/s when serving
with drafting). Its cause was not profiled.

## Patches (`patches/`, against `mw00/project-maya` at `bdd4167`)

| Commit | Change |
|---|---|
| `662e04f` | Installer accepts gfx1031 |
| `476a6f1` | Compile only for the chosen cards' architectures |
| `727c63d`, `6000cd0` | Build without rocWMMA on gfx10xx; F32 prompt attention |
| `76420ac` | Link `hip_expert_cache_staging` against `strata_prefill` |
| `0759f31` | HIP installer may split across more than two GPUs |

No kernel arithmetic was changed. The patches' `From:` header names the agent that wrote them;
apply with `git am`.

## Tests

54 of 56 ctest targets pass on gfx1031, including `hip_device_selftest`,
`hip_expert_kernel_parity` and `glm_mv_parity` (bit-identical), `hip_prefill_mmq_parity`, and
the 45-layer synthetic `glm_model_big_test`.

- `hip_prefill_native_batch` **fails**; it passes with `HIP_LAUNCH_BLOCKING=1`. Cause not found
  after three attempts. Its kernel is used only by the inherited Strata/Qwen engine, not GLM.
- `expert_multi_test` needs AVX-512, which this CPU lacks.
- Two installer unit tests fail by design after `476a6f1`.

## Running it yourself

Nothing here is tied to one machine: every path, port and address is a setting in
`scripts/env.sh`. The scripts were parameterised for publication and have **not been re-run
since**; the measurements above came from the same scripts with fixed paths.

### Requirements

- Linux, AMD GPUs supported by your ROCm, and a system ROCm 7.x in `ROCM_PATH` (default
  `/opt/rocm`) with `hipcc`, hipBLAS and rocBLAS kernels **for your card's architecture**.
  Check with `ls $ROCM_PATH/lib/rocblas/library | grep gfx1031` (substitute your architecture).
- `g++`, `git`, `curl`, `tmux`, and Python 3.10+ with venv (`python3-venv` on Debian/Ubuntu).
  CMake and Ninja are installed into the project's own `.venv` by its installer.
- RAM plus VRAM large enough to hold the model's experts (about 88 GB for Maya-S24), or decode
  falls back to disk. About 100 GB of disk per model.

### Setup

```sh
export MAYA_HOME=$HOME/maya-rdna2            # or edit scripts/env.sh
mkdir -p $MAYA_HOME && cd $MAYA_HOME
git clone https://github.com/mw00/project-maya.git src && cd src
git checkout -b rdna2 bdd4167
git am /path/to/this/repo/patches/*.patch
( umask 077; openssl rand -hex 24 > $MAYA_HOME/API_KEY )
./maya.sh --backend hip --setup --gpus 0,1,2,3,4,5 --context 131072 --no-vision --yes --plain   --no-start --model Maya-S24 --download-model --models-dir $MAYA_HOME/models   --env STRATA_GLM_PCIE_SHARE=0 --env STRATA_GLM_CPU_LANE=3 --env STRATA_GLM_MTP_KEEP=0   --env STRATA_GLM_RESERVE_MB=384 --env STRATA_GLM_RAM_HEADROOM_GB=10
/path/to/this/repo/scripts/start.sh
```

The installer writes `src/maya-maya-s24-hip.json`; `configs/*.example.json` show the two final
configs with paths replaced by `<MAYA_HOME>` and `<MAYA_MODELS>` (reference only, do not copy).
For a GGUF you already have, replace `--model ... --download-model --models-dir ...` with
`--gguf-dir <folder>`.

### What you must change for your machine

| Setting | Where | Change it when |
|---|---|---|
| `MAYA_HOME`, `MAYA_MODELS`, `MAYA_API_KEY_FILE`, `MAYA_PORT`, `ROCM_PATH` | `scripts/env.sh` | Always check; defaults are under `$HOME/maya-rdna2` |
| `MAYA_HOST` | `scripts/env.sh` | Default is `127.0.0.1`. Set `0.0.0.0` to serve your network |
| `--gpus` | setup command | Your GPU numbers, in the order `./maya.sh --backend hip --check` prints. Put cards in real slots first |
| Card architecture | `patches/0001` | The patch adds `gfx1031` only. For another RDNA2 card add its architecture to `HIP_ARCHS` in `maya.py` |
| `STRATA_GLM_CPU_LANE` | setup command | Set to your physical core count, or one less. Hyperthreads made it slower here |
| `STRATA_GLM_PCIE_SHARE=0` | setup command | Keep it if any card is on a slow link (x1 riser). With every card on x8/x16, leave it unset and let the engine choose |
| `STRATA_GLM_RESERVE_MB` | setup command | 384 is the lowest that worked on 12 GB headless cards. Use 1024 or more on a card that also drives a display |
| `STRATA_GLM_RAM_HEADROOM_GB` | setup command | Lower it if experts spill to disk (non-zero "disk reads/tok" in the engine log); raise it if prompts fail with a host-buffer error |
| `STRATA_GLM_TRUNK_KEEP_MAP` | `scripts/use-map.sh` | Optional speed/quality trade; see the quality table. Off means exact answers |
| `STRATA_GLM_SEQS`, `STRATA_GLM_SEQ_CTX` | setup command | Optional parallel conversations; costs some VRAM |

### Scripts

| Script | Purpose |
|---|---|
| `scripts/env.sh` | Shared settings, sourced by the others |
| `scripts/start.sh`, `stop.sh` | Start or stop the server in tmux session `maya` |
| `scripts/use-model.sh s24\|abliterated` | Switch between two installed configs and restart |
| `scripts/use-map.sh exact\|m1\|p1\|m3` | Switch trunk-keep map and restart |
| `scripts/try.sh LABEL GPUS KEY=VALUE...` | Re-run setup with extra engine settings, start on localhost, run the benchmark |
| `scripts/bench.py`, `conc.py` | Single-request and parallel benchmarks |
| `scripts/score.py`, `score2.py` | Trunk-keep quality scoring (the engine must be stopped) |
| `scripts/run-tests.sh` | Build and run the ctest suite on GPU 0 |
| `scripts/dl-huihui.sh` | Download and checksum the abliterated UD-IQ2_XXS quant |

## Settings that did not help

Eight CPU threads (6.7 vs 9.5 tok/s); hybrid CPU/PCIe lanes; `STRATA_GLM_PROMOTE=32`;
`STRATA_GLM_PROMOTE_FILL=6`; speculative head group of 2 or 4; 8-bit KV cache (within noise).
`STRATA_GLM_RESERVE_MB=128` failed with invalid routing on the first long answer.

## Known limits and unverified items

- VRAM is nearly full (about 11.75 of 11.98 GiB per card); 384 MB is the lowest reserve that passed.
- The abliterated model leaves about 5.5 GB of system RAM free during a prompt; only prompts up
  to 4.4K tokens were tested on it, and a 6 GB RAM headroom failed with a host-buffer error.
- Maya-S24 was validated at a 6 GB RAM headroom; its config now says 10 GB, which has not been run.
- No prompt longer than 28K tokens was run. No task-level quality evaluation was done.
- Prompts of a few thousand tokens read slower on six cards than on two (35 vs 58 tok/s).
- Nothing here was tested on any other RDNA2 card or ROCm version.

## Sources

- Project Maya: <https://github.com/mw00/project-maya> (MIT). Docs used: `README.md`,
  `docs/AMD_MAYA.md`, `docs/AMD_HIP.md`, `docs/SETTINGS.md`, `docs/MULTI_GPU.md`,
  `docs/GLM5-FLASH.md`, `docs/STRATA-README.md`. Trunk-keep: `docs/SETTINGS.md` and commit `528d2b4` (#103).
- Strata, the engine Maya is built on: <https://github.com/Niko1221/Strata> (MIT).
- ggml / llama.cpp, pinned at `3cf03257f219afbe7334045ff7c6a06ac68c627d`: <https://github.com/ggml-org/llama.cpp> (MIT).
- GLM-5.3-Flash by zai-org: <https://huggingface.co/zai-org/GLM-5.3-Flash> (MIT).
- Maya quants: <https://huggingface.co/peasantsmith/GLM-5.3-Flash-Maya-GGUF>.
- Abliterated GGUFs: <https://huggingface.co/huihui-ai/Huihui-GLM-5.3-Flash-abliterated-GGUF>,
  derived from <https://huggingface.co/unsloth/GLM-5.3-Flash-GGUF>.
- AMD ROCm / HIP / rocWMMA: <https://github.com/ROCm>.

Licensed under the MIT License (`LICENSE`), the same license as Project Maya, whose copyright
notice is kept because the patches derive from it. No model weights are in this repository.
