# Semantic Dependency Extension

Allows pages to specify that other pages should have their semantic data updated when the current page is saved.

**Note: [Extension:SemanticDependencyUpdater](https://www.mediawiki.org/wiki/Extension:SemanticDependencyUpdater) seems to do the same job, and is probably worth checking out once the site is running an up to date mediawiki version**


## Usage

In a template, use the parser function to declare a dependency:

```mediawiki
{{#semanticdependent:PageName}}
```

When the page containing this parser function is saved, `PageName` will have its semantic data refreshed automatically.

## Example

In `Template:Condition`:
```mediawiki
{{#semanticdependent:{{{Location|}}}}}
```

When a condition report is saved, the canyon page (Location) will automatically update its semantic properties (like `Has condition date`).

## Installation

Add to `LocalSettings.php`:

```php
wfLoadExtension( 'SemanticDependency' );
```

## Configuration

### Enable Logging

```php
// Enable debug logging (disabled by default)
$wgSemanticDependencyEnableLogging = true;

// Optional: Send logs to specific file
$wgDebugLogGroups['SemanticDependency'] = '/tmp/SemanticDependency.log';
```

Logs are also written to the PHP error log with `[SemanticDependency]` prefix.

## Requirements

- MediaWiki 1.39+
- Semantic MediaWiki 4+