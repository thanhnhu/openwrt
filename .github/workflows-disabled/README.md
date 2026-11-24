# Disabled upstream workflows

These are the upstream OpenWrt CI workflows. They were moved out of
`.github/workflows/` on the `viettel-32x6` branch so they never run in the
fork (GitHub only reads `.github/workflows/`).

To re-enable one, move it (and `scripts/` if it uses them) back:

```bash
git mv .github/workflows-disabled/<name>.yml .github/workflows/
```

The only active workflow on this branch is
`.github/workflows/build-viettel-32x6.yml` (manual trigger only).
