# ComfyUI

Automation to rebuild and start [ComfyUI](https://github.com/comfyanonymous/ComfyUI). It automates the following steps:

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
conda create --name ComfyUI python=3.13
```

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

* https://docs.comfy.org/tutorials/flux/flux1-krea-dev

