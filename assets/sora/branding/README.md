# Sora Branding Prompts

These prompts are for concept exploration that matches the app's graphite and champagne visual language.

Because Sora produces video rather than still images, the icon workflow is:
1. Generate a near-static 4 second clip with the icon concept centered.
2. Extract a frame.
3. Center-crop it to a square reference image.

Use the helper script:

```bash
bash ./scripts/run_branding_sora.sh dry-run
bash ./scripts/run_branding_sora.sh icon-preview
bash ./scripts/run_branding_sora.sh extract-icon-still ./out/icon-preview.mp4 ./out/icon-reference.png
```

Live generation requires:
- `OPENAI_API_KEY`
- Python `openai` package available to `python3`
