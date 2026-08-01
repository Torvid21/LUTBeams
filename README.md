# LUTBeams
Still fixing bugs and stuff ^^

Volumetric light beams for VRChat. As seen in **Stage Flight** and **Furality**.

Example uses:
1. Spotlights for light shows
2. Projector light for video players
3. Ambient light shafts

<img src="Media/20260730195451477.png" />

## Download
Either clone the whole project, or copy-paste Assets/LUTBeam/ into your project.

## Usage
1. place a LUTBeamManager prefab in the scene
2. place a LUTBeamSimple or LUTBeamAvatar prefab in the scene
3. ???

If you are putting it in an avatar, delete the ExplodeBounds script and scale the cube up manually instead so it doesn't cull.

## To change gobo (light cookie) images
Right click LUTBeamManager component and click "Generate Texture Array", then assign that array to your material.

<img src="Media/20260730221904896.png" width="75%"/>

## Use with VRSL
Don't know but should be easy to integrate.

## Attribution
All the code int Assets/LUTBeam/ is MIT / Public Domain.

Therinization image is by Nightshades

Tiles texture is from textures.com

Gobos textures are mostly by me, don't 100% remember.

## How?
Raymarching volumetrics per pixel is way too expensive, I get around this by baking raymarch results to a lookup texture (LUT), so that they can later be grabbed very fast at runtime.

Somewhat similar to Latrix Laser System by OwenTheProgrammer, though theirs is far more advanced.



