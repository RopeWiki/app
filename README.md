# RopeWiki Backend

This repository contains the deployment framework for the RopeWiki backend infrastructure.

At its hearth ropewiki is powered by [Mediawiki](https://www.mediawiki.org/wiki/MediaWiki) (the same as Wikipedia), along with an extension called [Semantic Mediawiki](https://www.semantic-mediawiki.org/wiki/Semantic_MediaWiki) which allows for meaningful connections between pieces of data.

Detailed documentation previously located here has moved to the [GitHub wiki](https://github.com/RopeWiki/app/wiki/).

_tl;dr - everything needed to make the site load lives here. What you actually see when the site loads does not live here._

## What lives here

Using this repo you can build and deploy the complete stack of services needed to run the website.

- deployment tools & helpers
- docker configs
- webserver & proxy server configs
- mediawiki configs
- mediawiki extensions & patches
- version control for PHP, MySQL, MediaWiki, SMW
- backup automation
- mail relay config

## What does not live here

Importantly, this repo does not contain:

- **Site Data** — The content of the site lives in a database and is distributed to developers separately. Note that something you may find confusing is that much of the site's code lives as pages inside MediaWiki itself. Logic powered by Semantic MediaWiki is heavily used via site templates, and JS/CSS is stored in special MediaWiki pages.
- **Images & Uploads** — Images and any other uploaded content (e.g. KML or PDF files) are located elsewhere too.
- **Javascript & CSS** — As already mentioned, these are actually part of the MediaWiki system itself, however we do keep their sources in GitHub: [js](https://github.com/RopeWiki/commonjs), [css](https://github.com/RopeWiki/commoncss).
- **Sensitive Content** — Passwords and the like are provided at runtime (usually via env vars) and not stored here.
