---
name: material-design-skills
description: "Guidelines and principles for generating user interfaces strictly following Material Design 3."
---

# Material Design 3 Skill

When tasked with designing or building UI components, you must adhere strictly to Google's Material Design 3 (M3) specifications.

## Core Principles

1. **Colors & Theming**:
   - Use dynamic color principles. Prefer primary, secondary, and tertiary colors over arbitrary custom colors.
   - Use distinct surface colors (Surface, Surface Container, Surface Container Low, etc.) to indicate elevation and depth, replacing heavy drop shadows where appropriate.
   - Ensure a minimum contrast ratio of 4.5:1 for standard text against backgrounds.

2. **Typography**:
   - Use the Roboto font or similar clean sans-serif typography.
   - Adhere to the M3 typography scale: Display, Headline, Title, Body, and Label. 
   - Avoid using more than two font families; stick to weight and size variations to establish hierarchy.

3. **Components & Layout**:
   - **Buttons**: Differentiate between Filled, Tonal, Outlined, and Text buttons based on the priority of the action. Always include rounded corners (typically fully rounded or small radii based on component type).
   - **Cards**: Use soft surface styling with a 1px border (Outlined Card) or subtle background changes (Filled Card) instead of stark drop shadows (Elevated Card), unless visual prominence is required.
   - **Spacing**: Use a baseline grid (4dp / 8dp grid system) for all padding, margins, and component alignments.

4. **Elevation**:
   - Elevation in M3 is conveyed through tonal surface colors and subtle shadows. Do not stack multiple heavy shadows. 

5. **Motion**:
   - UI states should transition smoothly (hover, active, pressed) using standard easing curves (e.g. `cubic-bezier(0.2, 0, 0, 1)`).

## Framework Guidance
If using a framework (like React or Flutter):
- For **React/Web**: Suggest using `@mui/material` (MUI v5+) or carefully crafting Tailwind CSS tokens that mirror the M3 design system.
- For **Flutter**: Ensure `useMaterial3: true` is set in the `ThemeData` and utilize built-in M3 widgets.
