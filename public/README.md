# `site/` — public overview page + API docs

Static front door for **https://partledger.jasonnoble.dev/**.

```
site/
├── index.html          # recruiter-facing project overview (root /)
├── logo.svg            # project logo (served at /logo.svg)
└── docs/
    ├── index.html      # Scalar API reference (served at /docs/)
    └── openapi.yaml     # spec copy with prod server added; refreshed from backend/doc/openapi.yaml
```

## Deploying

The Rails app is API-only, but Thruster/Rails serves anything in `public/` as static
files at the URL root. Copy these into the **real backend checkout's** `public/`:

```bash
cp site/index.html        <backend>/public/index.html
cp site/logo.svg          <backend>/public/logo.svg
cp -r site/docs           <backend>/public/docs
```

Then `/` → overview, `/docs/` → API reference, `/docs/openapi.yaml` → raw spec.

> The wrapper repo's `backend/` submodule is read-only — don't copy into it. Copy into
> the separate checkout you deploy from.

## Keeping the spec fresh

`docs/openapi.yaml` is a copy of `backend/doc/openapi.yaml` with a production `servers:`
entry prepended. After regenerating the spec, refresh it:

```bash
cp backend/doc/openapi.yaml site/docs/openapi.yaml
# then re-add the prod server line at the top of `servers:`
```

## Configuring links on the overview page

Edit the `CONFIG` block near the bottom of `index.html`. Empty string = button shows
"coming soon" / is disabled; fill each in as it goes live:

```js
const CONFIG = {
  frontendUrl: "",   // deployed React app
  backendRepo: "",   // GitHub (set when repo is public)
  frontendRepo: "",
  blogUrl: ""        // "How I Built This" post
};
```

The Scalar bundle is pinned (`@scalar/api-reference@1.58.0`) and loaded from jsDelivr.
