# PicDrop Extension

**Drag and drop images directly into the MediaWiki editor with automatic {{pic}} template insertion.**

## Features

- 🎯 **Exact cursor placement** - Drops images exactly where your cursor is
- 🎨 **Visual feedback** - Shows a blue overlay when dragging files over the editor
- 📝 **{{pic}} template** - Automatically inserts `{{pic|filename.jpg ~ }}` syntax
- 🏷️ **Auto-prefixing** - Adds page name to uploaded filenames (e.g., `Smith_Canyon_photo.jpg`)
- ⌨️ **Smart cursor** - Positions cursor inside description field after upload
- 📤 **Multiple files** - Supports dropping multiple images at once

## Usage

1. **Edit any wiki page** in wikitext mode
2. **Position your cursor** where you want the image
3. **Drag an image file** from your computer onto the textarea
4. **Drop the file** - you'll see a blue overlay with "Drop images here"
5. **Wait for upload** - notification will confirm success
6. **Add description** - cursor is positioned inside `{{pic|filename ~ [HERE]}}`

## How It Works

### Upload Process

When you drop an image:
1. Saves your cursor position
2. Uploads file with page name prefix (e.g., on page "Smith_Canyon", `photo.jpg` becomes `Smith_Canyon_photo.jpg`)
3. Inserts `{{pic|photo.jpg ~ }}` at saved cursor position
4. Positions cursor between `~` and `}}` for you to type the description

### Filename Handling

- **Input:** `my photo.jpg` on page "Smith Canyon"
- **Stored as:** `Smith_Canyon_my_photo.jpg`
- **Template uses:** `{{pic|my_photo.jpg ~ description}}`

The page name prefix is automatic (as expected by the {{pic}} template system) but the template itself uses just the base filename.

## File Support

- **Supported:** `.jpg`, `.jpeg`, `.png`, `.gif` (all image formats)
- **Rejected:** Non-image files show an error notification

## Visual Feedback

- **Dragging over editor:** Blue dashed border with overlay message
- **Uploading:** Info notification: "Uploading... filename"
- **Success:** Green notification: "Upload successful! Full_Filename.jpg"
- **Error:** Red notification with error details

## Installation

### 1. Extension Files

Already included in this directory:
- `extension.json` - Extension manifest
- `includes/Hooks.php` - PHP initialization
- `resources/PicDrop.js` - Drag-drop and upload logic
- `resources/PicDrop.css` - Visual feedback styles
- `i18n/en.json` - UI messages

### 2. LocalSettings.php

Add to your LocalSettings.php:
```php
wfLoadExtension( 'PicDrop' );
```

### 3. Docker Rebuild

If running in Docker, rebuild the container:
```bash
cd /path/to/app
docker-compose build webserver
docker-compose up -d
```

## Technical Details

### JavaScript API Used

- `$('#wpTextbox1').textSelection('getCaretPosition')` - Save cursor position
- `$('#wpTextbox1').textSelection('setSelection', {start, end})` - Restore cursor
- `$('#wpTextbox1').textSelection('encapsulateSelection', {pre: text})` - Insert text
- MediaWiki API `action=upload` - Upload files

### Configuration Passed to JavaScript

From PHP (Hooks.php):
```javascript
picDropConfig = {
    pageName: 'Smith_Canyon',
    pageNamespace: 0,
    editToken: '...'
}
```

### Browser Compatibility

Uses standard HTML5 drag-and-drop APIs:
- `dragenter` - Show visual feedback
- `dragleave` - Hide visual feedback
- `dragover` - Prevent default to allow drop
- `drop` - Handle file upload

### Dependencies

- MediaWiki 1.39+
- jQuery (included with MediaWiki)
- jQuery.textSelection plugin (included with MediaWiki)

## Comparison with MsUpload

| Feature | MsUpload | PicDrop |
|---------|----------|---------|
| Upload UI | Button/bar above editor | Direct drag-drop |
| Syntax | `[[File:...]]` | `{{pic\|...\}}` |
| Placement | End of textarea | Exact cursor position |
| Page prefix | Manual | Automatic |
| Cursor control | No | Yes - in description field |

## Troubleshooting

### Extension not loading

Check browser console for errors:
```javascript
mw.config.get('picDropConfig')
```

Should return an object with `pageName`, `pageNamespace`, `editToken`.

### Upload fails

1. Check you're logged in (need edit token)
2. Check file size limits in php.ini
3. Check MediaWiki upload permissions
4. Check browser console for API errors

### Template not inserted

1. Ensure cursor was in the textarea before dropping
2. Check that upload completed successfully
3. Refresh page and try again

## Development

### Testing locally

1. Edit any page: `https://ropewiki.attack-kitten.com/Test_Page/edit`
2. Open browser DevTools console
3. Drop an image and watch for API calls
4. Check inserted text in textarea

### Debugging

Enable verbose logging in PicDrop.js by adding:
```javascript
console.log('PicDrop:', action, data);
```

### Modifying

- **Change template format:** Edit `onUploadSuccess()` in `resources/PicDrop.js`
- **Change visual feedback:** Edit `resources/PicDrop.css`
- **Change upload behavior:** Edit `uploadFile()` in `resources/PicDrop.js`

## Future Enhancements

Possible improvements:
- [ ] Drag-drop onto VisualEditor (not just wikitext mode)
- [ ] Image preview before upload
- [ ] Batch upload progress indicator
- [ ] Custom filename prompt
- [ ] Auto-description from EXIF data
- [ ] Support for video files with appropriate templates

## License

GPL-2.0-or-later (matching MediaWiki)

## Credits

Created for RopeWiki.com to streamline the canyon documentation workflow.

Inspired by MsUpload extension but redesigned for {{pic}} template integration and precise cursor control.
