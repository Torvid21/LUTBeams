/**
Copyright 2024 Khronos Group

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
**/

class KhronosNeutralTonemapper
{
    float3 Map(float3 color) 
    {
        const float startCompression = 0.8 - 0.04;
        const float desaturation = 0.15;

        float x = min(color.r, min(color.g, color.b));
        float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
        color -= offset;

        float peak = max(color.r, max(color.g, color.b));
        if (peak < startCompression) return color;

        const float d = 1.0 - startCompression;
        float newPeak = 1.0 - d * d / (peak + d - startCompression);
        color *= newPeak / peak;

        float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
        return lerp(color, newPeak * float3(1, 1, 1), g);
    }
};