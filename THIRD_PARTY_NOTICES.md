# Third-party sources and distribution scope

This document records provenance. It does not replace upstream licenses or grant new rights to project code or artwork.

| Component | Source / scope |
|---|---|
| iOS application and product artwork | Existing project supplied for development. No repository-wide open-source license has been designated. |
| ESP32-S3 integration firmware | Developed against the supplied `nomi_main.zip` prototype source. Camera wiring/driver provenance and remaining distribution questions are recorded in [firmware/README.md](firmware/README.md). The original private archive and credentials are excluded. |
| Chinese-food model | [Albertbeta123/resnet-50-chinese-food](https://huggingface.co/Albertbeta123/resnet-50-chinese-food), revision `1ce5801e5905f15de1c4e55c89ef2a8cd6d6a97c`. The model card declares Apache-2.0; training-data rights require separate consideration. Weights are not distributed in this repository. Reviewed metadata, label mapping, checksums and evaluation scripts are included. |
| ChineseFoodNet training data | Not included. Dataset rights are distinct from the model/code license. See [model evaluation](docs/model-evaluation.md). |
| Public evaluation photographs | Not included in this repository. Authors, source URLs and photo licenses are recorded in [model evaluation](docs/model-evaluation.md); screenshots in the README show the app UI, not those photographs. |
| Python / Arduino dependencies | Installed separately and governed by their own licenses. Versions are recorded in the tools and firmware documentation. No dependency source tree is vendored here. |
| README badges | Rendered by [Shields.io](https://shields.io/). They describe the stack, not a live CI status. |

Private device backups, secrets, signing material, model packages and local build outputs are excluded through `.gitignore` and an explicit publication review. Existing historical evidence files refer to the original project name; they are retained as records, not rewritten as new test results.
