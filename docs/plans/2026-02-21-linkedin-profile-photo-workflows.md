# LinkedIn Profile Photo Workflows Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create two ComfyUI workflows for turning uploaded photos into professional LinkedIn headshots — one enhancement-based, one AI-generation-based.

**Architecture:** Two standalone workflow JSON files in the ComfyUI visual graph format (matching the existing `character_infill_to_3d.json` structure). Infrastructure changes to `extra_model_paths.yaml` and `entrypoint.sh` to support the new PuLID model directory.

**Tech Stack:** ComfyUI workflow JSON (v0.4 format), Flux Dev/Fill models, PuLID-Flux, BRIA RMBG, Impact Pack SEGS

---

### Task 1: Add PuLID model path to infrastructure

**Files:**
- Modify: `apps/comfyui/defaults/extra_model_paths.yaml`
- Modify: `apps/comfyui/entrypoint.sh`

**Step 1: Add `pulid` to extra_model_paths.yaml**

Add after the `photomaker` line in `apps/comfyui/defaults/extra_model_paths.yaml`:

```yaml
  pulid: models/pulid/
```

**Step 2: Add `pulid` to model directories in entrypoint.sh**

Add `"pulid"` to the `MODEL_DIRECTORIES` array in `apps/comfyui/entrypoint.sh` (after `"photomaker"`).

**Step 3: Verify**

Visually confirm the YAML is valid (proper indentation, consistent with other entries). Confirm the entrypoint array entry matches the pattern.

**Step 4: Commit**

```bash
git add apps/comfyui/defaults/extra_model_paths.yaml apps/comfyui/entrypoint.sh
git commit -m "feat(comfyui): add pulid model directory for PuLID-Flux support"
```

---

### Task 2: Create the enhance workflow (`linkedin_enhance.json`)

**Files:**
- Create: `apps/comfyui/workflows/linkedin_enhance.json`

**Reference:** Follow the exact node/link structure used in `apps/comfyui/workflows/character_infill_to_3d.json` for field names, positions, and format.

**Step 1: Write the workflow JSON**

Create `apps/comfyui/workflows/linkedin_enhance.json` with these nodes (all using ComfyUI v0.4 format):

| ID | Type | Purpose | Key widgets |
|----|------|---------|-------------|
| 1 | LoadImage | Input photo | `["photo.png", "image"]` |
| 2 | FaceDetailer (Impact Pack) | Detect face, produce cropped bounding | SEGS-based face detection |
| 3 | ImageCrop | Crop to head/shoulders region | Based on face bbox, padded |
| 4 | ImageScale | Resize to 1024x1024 | `[1024, 1024, "lanczos", "center"]` |
| 5 | BRIA_RMBG_ModelLoader_Zho | Load BG removal model | (no widgets) |
| 6 | BRIA_RMBG_Zho | Remove background | Takes image + rmbg_model |
| 7 | EmptyImage | Professional gray background | `[1024, 1024, 1, 14277081]` (hex #D9D9D9) |
| 8 | ImageCompositeMasked | Composite person onto bg | `[0, 0, false]` |
| 9 | UNETLoader | Load Flux Fill model | `["flux1-fill-dev.safetensors", "fp8_e4m3fn"]` |
| 10 | DualCLIPLoader | Load CLIP models | `["clip_l.safetensors", "t5xxl_fp8_e4m3fn.safetensors", "flux"]` |
| 11 | VAELoader | Load VAE | `["ae.safetensors"]` |
| 12 | CLIPTextEncodeFlux | Positive prompt | `["professional headshot, studio lighting, clean background, sharp focus, high quality portrait photography", "...", 4.0]` |
| 13 | CLIPTextEncodeFlux | Negative prompt (empty) | `["", "", 4.0]` |
| 14 | InpaintModelConditioning | Prepare inpaint conditioning | Takes positive, negative, vae, composite image, edge mask |
| 15 | KSampler | Denoise edges | `[seed, "randomize", 15, 3.5, "euler", "simple", 0.4]` (low denoise for edge smoothing) |
| 16 | VAEDecode | Decode latent | Standard |
| 17 | ImageScale | Final resize to exact 1024x1024 | `[1024, 1024, "lanczos", "disabled"]` |
| 18 | PreviewImage | Preview result | Title: "Enhanced Headshot" |
| 19 | SaveImage | Save output | `["linkedin_enhanced"]` |

**Groups:**
1. "1. Load & Crop Face" — nodes 1-4, blue (#3f789e)
2. "2. Background Replacement" — nodes 5-8, green (#8A8)
3. "3. Edge Smoothing (Flux Fill)" — nodes 9-16, orange (#a86)
4. "4. Output" — nodes 17-19, purple (#88a)

**Links:** Wire according to the pipeline: LoadImage → crop → scale → RMBG → composite → inpaint conditioning → sample → decode → scale → save.

**Step 2: Validate JSON structure**

Run: `python3 -m json.tool apps/comfyui/workflows/linkedin_enhance.json > /dev/null`
Expected: No errors (valid JSON).

**Step 3: Commit**

```bash
git add apps/comfyui/workflows/linkedin_enhance.json
git commit -m "feat(comfyui): add linkedin photo enhancement workflow"
```

---

### Task 3: Create the generate workflow (`linkedin_generate.json`)

**Files:**
- Create: `apps/comfyui/workflows/linkedin_generate.json`

**Step 1: Write the workflow JSON**

Create `apps/comfyui/workflows/linkedin_generate.json` with these nodes:

**Input Section:**

| ID | Type | Purpose | Key widgets |
|----|------|---------|-------------|
| 1 | LoadImage | Reference face photo | `["photo.png", "image"]` |
| 2 | PreviewImage | Show original | Title: "Original Face" |
| 3 | ImageScale | Resize original for comparison | `[512, 512, "lanczos", "center"]` |

**Model Loading:**

| ID | Type | Purpose | Key widgets |
|----|------|---------|-------------|
| 4 | UNETLoader | Load Flux Dev | `["flux1-dev.safetensors", "fp8_e4m3fn"]` |
| 5 | DualCLIPLoader | Load CLIP | `["clip_l.safetensors", "t5xxl_fp8_e4m3fn.safetensors", "flux"]` |
| 6 | VAELoader | Load VAE | `["ae.safetensors"]` |

**PuLID Face Identity:**

| ID | Type | Purpose | Key widgets |
|----|------|---------|-------------|
| 7 | PulidFluxModelLoader | Load PuLID model | `["pulid_flux_v0.9.1.safetensors"]` |
| 8 | PulidFluxEvaClipLoader | Load EVA CLIP | (no widgets) |
| 9 | ApplyPulidFlux | Apply face identity to model | `[0.9, 0, 3, "fidelity"]` (weight 0.9, start 0, end 3, mode) |

**Style Prompts (3 groups, user mutes 2 of 3):**

| ID | Type | Style | Prompt |
|----|------|-------|--------|
| 10 | CLIPTextEncodeFlux | Corporate | `"professional corporate headshot, formal business attire, suit, neutral gray background, studio lighting, confident expression, sharp focus on face, Canon EOS R5, 85mm f/1.4 lens"` |
| 11 | CLIPTextEncodeFlux | Creative | `"professional headshot, smart casual attire, warm studio lighting, subtle colored background, approachable expression, modern professional, sharp focus, high quality photography"` |
| 12 | CLIPTextEncodeFlux | Casual | `"professional headshot, business casual, natural soft lighting, clean background, friendly smile, relaxed but professional, soft bokeh, high quality photography"` |
| 13 | CLIPTextEncodeFlux | Negative | `"deformed, blurry, bad anatomy, extra limbs, watermark, text, low quality, cartoon, illustration, painting, ugly, disfigured, extra fingers"` |

Nodes 10-12 each connect to the sampler. Only one should be active (mode: 0), the other two muted (mode: 4). Default active: Corporate.

**Generation:**

| ID | Type | Purpose | Key widgets |
|----|------|---------|-------------|
| 14 | EmptySD3LatentImage | Empty latent | `[1024, 1024, 1]` |
| 15 | KSampler | Generate portrait | `[seed, "randomize", 20, 3.5, "euler", "simple", 1.0]` |
| 16 | VAEDecode | Decode | Standard |

**Output:**

| ID | Type | Purpose | Key widgets |
|----|------|---------|-------------|
| 17 | ImageScale | Ensure 1024x1024 | `[1024, 1024, "lanczos", "disabled"]` |
| 18 | ImageBatch | Combine original + generated | For side-by-side comparison |
| 19 | PreviewImage | Comparison preview | Title: "Comparison: Original vs Generated" |
| 20 | SaveImage | Save generated portrait | `["linkedin_generated"]` |
| 21 | PreviewImage | Preview generated only | Title: "Generated Portrait" |

**Groups:**
1. "1. Input Face" — nodes 1-3, blue (#3f789e)
2. "2. Model Loading" — nodes 4-6, gray (#888)
3. "3. PuLID Face Identity" — nodes 7-9, red (#a66)
4. "4a. Style: Corporate (Active)" — node 10, green (#8A8)
5. "4b. Style: Creative (Muted)" — node 11, green (#8A8)
6. "4c. Style: Casual (Muted)" — node 12, green (#8A8)
7. "5. Generation" — nodes 13-16, orange (#a86)
8. "6. Output & Comparison" — nodes 17-21, purple (#88a)

**Step 2: Validate JSON structure**

Run: `python3 -m json.tool apps/comfyui/workflows/linkedin_generate.json > /dev/null`
Expected: No errors.

**Step 3: Commit**

```bash
git add apps/comfyui/workflows/linkedin_generate.json
git commit -m "feat(comfyui): add linkedin AI portrait generation workflow with PuLID-Flux"
```

---

### Task 4: Final validation and documentation commit

**Files:**
- Verify: `apps/comfyui/workflows/linkedin_enhance.json`
- Verify: `apps/comfyui/workflows/linkedin_generate.json`
- Already committed: `docs/plans/2026-02-21-linkedin-profile-photo-workflows-design.md`

**Step 1: Validate both workflow JSONs parse correctly**

```bash
python3 -m json.tool apps/comfyui/workflows/linkedin_enhance.json > /dev/null && echo "enhance: OK"
python3 -m json.tool apps/comfyui/workflows/linkedin_generate.json > /dev/null && echo "generate: OK"
```

**Step 2: Verify node type consistency**

Check that all node `type` fields reference real ComfyUI node types:
- Core: LoadImage, ImageScale, PreviewImage, SaveImage, EmptyImage, ImageCompositeMasked, ImageBatch, KSampler, VAEDecode, VAELoader, UNETLoader, DualCLIPLoader, CLIPTextEncodeFlux, InpaintModelConditioning, ImagePadForOutpaint, EmptySD3LatentImage
- BRIA RMBG: BRIA_RMBG_ModelLoader_Zho, BRIA_RMBG_Zho
- Impact Pack: FaceDetailer (or UltralyticsDetectorProvider + SAMLoader for SEGS)
- PuLID-Flux: PulidFluxModelLoader, PulidFluxEvaClipLoader, ApplyPulidFlux

**Step 3: Commit design doc**

```bash
git add docs/plans/
git commit -m "docs: add linkedin profile photo workflow design and implementation plan"
```

---

## Required Model Downloads (user action)

Before using the workflows, the user must download:

**For generate workflow:**
1. `flux1-dev.safetensors` (or fp8 variant) → `/models/diffusion_models/`
2. `pulid_flux_v0.9.1.safetensors` → `/models/pulid/`
3. `EVA02_CLIP_L_336_psz14_s6B.pt` → `/models/clip_vision/`

**Custom nodes to install via ComfyUI-Manager:**
1. ComfyUI-Impact-Pack (face detection for enhance workflow)
2. ComfyUI-PuLID-Flux (face identity for generate workflow)

## Style Switching Guide

In `linkedin_generate.json`, switch styles by muting/unmuting groups:
- Right-click a group → "Set Mode" → "Mute" to disable a style
- Ensure exactly one style group is active (mode: 0), others muted (mode: 4)
