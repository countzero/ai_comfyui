# ComfyUI

Instructions on how to manually install [ComfyUI](https://github.com/comfyanonymous/ComfyUI) on a machine with a NVIDIA GPU. This includes a script that automates the following steps:

1. Fetching the latest version of [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
2. Installing specifiy PyTorch packages with NVIDIA support
3. Updating the Python dependencies of ComfyUI
4. Starting the ComfyUI server

## Installation

### 1. Install Prerequisites

Download and install the latest versions:

* [Cuda](https://developer.nvidia.com/cuda-downloads)
* [Git Large File Storage](https://git-lfs.com)
* [Git](https://git-scm.com/download)
* [Miniconda](https://conda.io/projects/conda/en/stable/user-guide/install)

### 2. Clone the repository from GitHub

Clone the repository to a nice place on your machine via:

```PowerShell
git clone --recurse-submodules git@github.com:countzero/ai_comfyui.git
```

### 3. Create a new Conda environment

Create a new Conda environment for this project with a specific version of Python:

```PowerShell
conda create --name ComfyUI python=3.14
```

> [!NOTE]
> ComfyUI considers Python 3.13 its best tested target. Python 3.14 works, but some custom nodes may have issues with it.

### 4. Initialize Conda for shell interaction

To make Conda available in you current shell execute the following:

```PowerShell
conda init
```

> [!TIP]
> You can always revert this via `conda init --reverse`.

### 5. Execute the build script

To build ComfyUI and its depdendencies execute the script:

```PowerShell
./rebuild_comfyui.ps1
```

> [!TIP]
> If PowerShell is not configured to execute files allow it by executing the following in an elevated PowerShell: `Set-ExecutionPolicy RemoteSigned`

### 6. Install and use a specific model

Follow the ComfyUI tutorial on how to use a specific model, e.g.:

* https://docs.comfy.org/tutorials/flux/flux-2-dev
* https://docs.comfy.org/tutorials/flux/flux-2-klein#flux-2-klein-9b-workflows

## Usage

### Workflows

The workflows in [`workflows`](./workflows) are the durable copies. Running
`./start_comfyui.ps1` publishes them into ComfyUI's sidebar via
[`deploy_workflows.ps1`](./deploy_workflows.ps1):

| Sidebar | Model | Configuration |
|---|---|---|
| FLUX.2 Klein 9B → 1 Turbo | klein 9B distilled | 1440², 4 steps, CFG 1 |
| FLUX.2 Klein 9B → 2 Draft | klein 9B base | 1440², 20 steps, CFG 5 |
| FLUX.2 Klein 9B → 3 Print | klein 9B base | 1440², 28 steps, CFG 5, 4x upscale → 19 MP |
| FLUX.2 Klein 9B → 4 Edit | klein 9B distilled | reference-sized, 4 steps, CFG 1 |
| Utility → Upscale 4x | none | 4xNomos2_hq_dat2 |

Each has an `*_api.json` twin for driving `POST /prompt` directly.

> [!NOTE]
> ComfyUI reads the sidebar from `vendor/ComfyUI/user/default/workflows`, which
> is gitignored and is wiped by a submodule re-clone. If the sidebar is empty,
> run `./deploy_workflows.ps1`.

### Documentation

* [Hardware profile: 16 GiB Ada + Klein 9B](./docs/hardware-16gb-ada.md) — current machine, measured settings
* [Hardware profile: 24 GiB Blackwell + FLUX.2-dev](./docs/hardware-24gb-blackwell.md) — archived
* [FLUX.2 model manifest](./docs/models.md) — sources, sizes, encoder compatibility

