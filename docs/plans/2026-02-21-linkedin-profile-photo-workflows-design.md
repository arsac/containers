# LinkedIn Professional Profile Photo Workflows

## Overview

Two ComfyUI workflows for creating professional LinkedIn profile photos from uploaded pictures.

- **linkedin_enhance.json** — Enhance an existing photo into a professional headshot
- **linkedin_generate.json** — AI-generate a new professional portrait preserving the uploaded face

Both output 1024x1024 high-res square images.

## Workflow 1: Photo Enhancement (`linkedin_enhance.json`)

Takes an existing photo and transforms it into a professional-looking headshot.

### Pipeline

```
LoadImage
  -> Face detection + crop (head/shoulders framing, ~60% of frame)
  -> ImageResize (1024x1024 square, center on face)
  -> BRIA RMBG (remove original background)
  -> ImageCompositeMasked (composite onto professional gradient background)
  -> Flux Fill Inpaint (smooth edges, fix lighting at boundary)
  -> ImageBlend (slight warm color grade)
  -> ImageScale (ensure exact 1024x1024)
  -> SaveImage (PNG)
```

### Models (all already available)

| Model | Path |
|-------|------|
| flux1-fill-dev.safetensors | /models/diffusion_models/ |
| clip_l.safetensors | /models/text_encoders/ |
| t5xxl_fp8_e4m3fn.safetensors | /models/text_encoders/ |
| ae.safetensors | /models/vae/ |
| BRIA RMBG model | (via custom node) |

### Custom Nodes Required

- **ComfyUI-BRIA_AI-RMBG** — background removal (already installed)
- **ComfyUI-Impact-Pack** — face detection via SEGS for auto-crop framing

### Background Options

Professional gradient background generated via EmptyImage node (soft gray, hex ~#E8E8E8 to #D0D0D0) or a user-uploaded studio background.

## Workflow 2: AI-Generated Portrait (`linkedin_generate.json`)

Generates a new professional studio headshot using PuLID-Flux for face identity preservation.

### Pipeline

```
LoadImage (reference face)
  +-> PuLID-Flux (extract face identity)
  +-> PreviewImage ("Original Face")
  +-> ImageResize (for comparison)

Style Selector (mute groups):
  Corporate | Creative | Casual Professional
  -> CLIPTextEncodeFlux (selected style prompt)

CLIPTextEncodeFlux (negative prompt)

Flux Dev + PuLID conditioning + style prompt
  -> KSampler (steps: 20, cfg: 3.5, euler/simple)
  -> VAEDecode
  -> ImageScale (1024x1024)
  +-> SaveImage
  +-> Concat with resized original -> PreviewImage ("Comparison")
```

### Style Presets

| Style | Prompt |
|-------|--------|
| Corporate | professional corporate headshot, formal business attire, suit, neutral gray background, studio lighting, confident expression, sharp focus, Canon EOS R5, 85mm f/1.4 |
| Creative | professional headshot, smart casual attire, warm studio lighting, subtle colored background, approachable expression, modern professional, sharp focus, high quality |
| Casual Professional | professional headshot, business casual, natural soft lighting, clean background, friendly smile, relaxed but professional, bokeh, high quality photography |

**Negative prompt (shared):** deformed, blurry, bad anatomy, extra limbs, watermark, text, low quality, cartoon, illustration, painting, ugly, disfigured

### Key Parameters

| Parameter | Value |
|-----------|-------|
| PuLID weight | 0.8-1.0 |
| CFG scale | 3.5 |
| Steps | 20 |
| Sampler | euler |
| Scheduler | simple |
| Output size | 1024x1024 |

### Models Required

| Model | Path | Status |
|-------|------|--------|
| flux1-dev (or fp8 variant) | /models/diffusion_models/ | Needs download if not present |
| clip_l.safetensors | /models/text_encoders/ | Already available |
| t5xxl_fp8_e4m3fn.safetensors | /models/text_encoders/ | Already available |
| ae.safetensors | /models/vae/ | Already available |
| pulid_flux_v0.9.1.safetensors | /models/pulid/ | Needs download |
| EVA02_CLIP_L_336_psz14_s6B.pt | /models/clip_vision/ | Needs download |

### Custom Nodes Required

- **ComfyUI-PuLID-Flux** — face identity injection into Flux generation

### Face Comparison Preview

Side-by-side output showing original uploaded face next to the generated portrait, using ImageBatch or horizontal concat for quick quality validation.

## File Locations

Both workflow files go in: `apps/comfyui/workflows/`

- `apps/comfyui/workflows/linkedin_enhance.json`
- `apps/comfyui/workflows/linkedin_generate.json`
