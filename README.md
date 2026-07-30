# LUTBeams
Fast (ish) volumetric light beams for VRChat, As seen in FURALITY and STAGE FLIGHT. <3

Example use cases:
1. Spotlights for light shows
2. Projector light for video players
3. Ambient light shafts

<img src="Media/20260730195451477.png" />

## Usage
1. place a LUTBeamManager in the scene
2. place a LUTBeam in the scene
3. ???

## To change gobo images
Replace the images in the LUTBeamManager, then right click it and press "Generate Materials". This will update the texture arrays with your new gobos.

<img src="Media/20260730221904896.png" width="75%"/>

## Use with VRSL
don't know but should be easy to integrate.

## How?
Raymarching volumetrics per pixel is way too expensive, LUTBeams gets around this by baking raymarch results to a lookup texture (LUT), so that they can be grabbed very fast at runtime.

Somewhat similar to Latrix Laser System by OwenThe Programmer, though theirs is far more advanced.