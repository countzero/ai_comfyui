# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added
- [Workflows] Add Krea 2 Turbo Text to Image and Print workflows, with an optional LLM prompt enhancer that is off by default

### Fixed
- [Documentation] Correct docs/models.md: the int8 quantization gate is by backend, not by GPU tensor cores, so the bf16 Qwen-Image-2.1 files are not required on an older NVIDIA card

## [1.0.1] - 2026-09-21

### Added
- [Documentation] Add docs/build.md covering the submodule lifecycle and the Python requirements layering

### Changed
- [Documentation] Adopt Keep a Changelog with component tags

### Removed
- [Build] Remove the -latest switch from rebuild_comfyui.ps1

### Fixed
- [Build] Track ComfyUI's latest release again on a bare rebuild_comfyui.ps1 run
- [Build] Pin the custom-node submodules to their recorded commits instead of advancing them on every build
- [Build] Reject an unrecognized argument to rebuild_comfyui.ps1 instead of silently ignoring it

## [1.0.0] - 2026-09-21

### Added
- [Build] Add -latest to rebuild_comfyui.ps1 to move the submodule pointers to upstream's latest release
- [Workflows] Warn on a workflow missing its _ui.json or _api.json twin when deploying
- [Project] Add an MIT license

### Changed
- [Build] Restore the recorded submodule pointers on a bare rebuild_comfyui.ps1 run
