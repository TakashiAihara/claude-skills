# claude-skills

General-purpose Claude Code skills, published as the `skills` plugin of the `takashiaihara` marketplace.

| Skill | What it does |
|---|---|
| [animated-step-slides](skills/animated-step-slides/SKILL.md) | Single-file HTML slides for spec documents: each press of → moves a diagram one step, with checkers for fit and steps |

## Install

As a Claude Code plugin (skills are called as `skills:<name>`):

```bash
claude plugin marketplace add TakashiAihara/claude-skills
claude plugin install skills@takashiaihara
```

As plain skills for any agent that reads `SKILL.md`:

```bash
npx skills add TakashiAihara/claude-skills
```
