# Changelog

This changelog follows [Common Changelog](https://common-changelog.org) and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-21

_`rebuild_comfyui.ps1` no longer upgrades ComfyUI on a bare run: it restores the recorded submodule pointers, and `-latest` opts back into the old behavior._

### Changed

- Restore the recorded submodule pointers on a bare `rebuild_comfyui.ps1` run.

### Added

- Add `-latest` to `rebuild_comfyui.ps1`, which moves the submodule pointers to upstream's latest release.
- Warn on a workflow missing its `_ui.json` or `_api.json` twin when deploying.
- Add an MIT license.

[1.0.0]: https://github.com/countzero/ai_comfyui/releases/tag/v1.0.0
