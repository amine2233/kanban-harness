# Documentation site

[Docusaurus](https://docusaurus.io) site for MVP Dashboard: features and architecture of the
server, the CLI, MCP and the web app, plus the design notes under _Conceptions_.

```bash
mise run docs          # live reload on http://localhost:3000
mise run docs:build    # static site in website/build/ — CI runs this; broken links fail the build
```

Pages live in `docs/`; the sidebar is `sidebars.ts`. The two conception pages are copies of
`../docs/conceptions/*.md` with a front matter — keep the originals as the source and re-copy
when they change.
