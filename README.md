# KeyboardGlass 0.1.3

Target: iOS 17.2.1 / RootHide, all App system keyboards. Author: Ning&Hung Phan.

The keyboard background uses the original Glassify Regular platter material with no tab buttons, labels, pill, or lens. Candidate strip, keyboard body, and expand area retain the first-version shared background placement and arrow interaction.

Settings -> Keyboard Glass -> Glass Mode selects:
- Fixed Glass (default): the original Glassify Regular shader is executed at build time over the documented neutral 128/255 scene; the device displays the resulting light/dark PNG and does not run Glassify Metal.
- On-demand Glass: the original Glassify Regular GLSGlassView is used after a single local background snapshot on keyboard show, size, or appearance changes. `tracksBackdropMotion` stays off; there is no continuous display-link refresh. If the host cannot be read, the fixed Glassify asset remains visible.

Vendor/Glassify files are checked against revision a8e52aa9c015502fb68d5f81687698f11df6977d and are not modified. Build-time provenance records the fixed scene, original factory fields, output hashes, and whether native GPU baking completed. The runtime dylib links the original Glassify platform/core code for on-demand mode and carries the original shader metallib plus fixed assets.

No device install, injection, or runtime visual test is implied by source or CI checks.
