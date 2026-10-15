# Public source snapshot

This repository contains a reviewed source snapshot. Original Git history, credentials, personal records, local signing identities, device diagnostics, build outputs, downloaded model weights, firmware, and unreviewed media are excluded. Existing upstream license and attribution files apply to their respective components. Publication does not grant a new license to third-party content.

Configure your own Apple signing team to run native apps on a physical device. Downloaded datasets, binary runtimes, fonts, demo media, and models may need to be obtained separately using the documented upstream sources or fetch/build tools. This publication review does not certify that this snapshot builds or runs.

## Project setup and omitted assets

The source package and XcodeGen manifest are retained. Screenshots, temporary interface snapshots, workflow automation and machine/device calibration evidence are omitted. `Tools/build.sh` no longer supplies a physical device identifier; set `B2_DEVICE_ID` to your own device only when using its physical-device commands. Generate a project with XcodeGen as needed. The driver retains development hold/ownership conventions documented in the source; review those before using it as a general build script.
