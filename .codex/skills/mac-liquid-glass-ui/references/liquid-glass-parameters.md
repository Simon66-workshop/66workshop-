# Liquid Glass Parameters

Use these as starting points, then tune with screenshots.

## Card And Capsule Defaults

| Area | Range |
| --- | --- |
| Main glass alpha | 0.10-0.18 for transparent capsules, 0.32-0.55 for larger cards |
| Blur/material | ultraThinMaterial or 18-32 px conceptual blur |
| Saturation | 1.10-1.35 |
| Brightness | 1.08-1.25 |
| Edge thickness | 4-8 px |
| Outer rim highlight | 0.60-0.90 opacity equivalent |
| Bottom depth | 0.06-0.14 opacity equivalent |
| Corner attenuation feather | 6-9 px |
| Floating shadow | bottom ellipse, 10-18% opacity, 12-18 px blur |
| Contact shadow | bottom ellipse, 8-12% opacity, 5-8 px blur |

## SDF-Style Edge Logic

Use this logic conceptually even when implementing in SwiftUI shapes and masks.

```glsl
float cornerProximity(vec2 p, vec2 halfSize, float radius, float feather) {
  float cx = smoothstep(halfSize.x - radius - feather,
                        halfSize.x - radius + feather,
                        abs(p.x));
  float cy = smoothstep(halfSize.y - radius - feather,
                        halfSize.y - radius + feather,
                        abs(p.y));
  return cx * cy;
}

float straightMaskX(vec2 p, vec2 halfSize, float radius, float feather) {
  float limit = halfSize.x - radius;
  return 1.0 - smoothstep(limit - feather, limit + 1.0, abs(p.x));
}

float straightMaskY(vec2 p, vec2 halfSize, float radius, float feather) {
  float limit = halfSize.y - radius;
  return 1.0 - smoothstep(limit - feather, limit + 1.0, abs(p.y));
}
```

Apply edge light only to the relevant strips:

- `topGlow *= topStrip * cornerFadeStrong`
- `leftGlow *= leftStrip * cornerFadeStrong`
- `bottomDepth *= bottomStrip`
- `rightDepth *= rightStrip`
- `rim *= cornerFadeSoft`

This keeps straight edges expressive while preventing rounded corners from getting dirty.

## Status Color Guidance

Use semantic color as an accent, not as an opaque fill:

- Running: clean blue, readable title, blue glass orb body.
- Pending: amber title should be deeper/readable; orb gets amber wash/rim, not full yellow fill.
- Done: stable green accent, not candy neon.
- Blocked: red rim/wash, but preserve glass volume.
- Idle: gray-blue with enough contrast.
- Observed: cyan accent without overpowering the body.

## Common Failure Modes

- One frosted rectangle: add edge thickness, rim, internal diffusion, and content micro-surfaces.
- Dirty corners: split shadows from edge thickness and add corner attenuation.
- Plastic shell: reduce center opacity and dark edges; strengthen rim/refraction instead.
- Blurry text: reduce text shadow, add local haze, increase text contrast/weight.
- Laggy interactions: remove delayed click paths and avoid disk writes during drag.
