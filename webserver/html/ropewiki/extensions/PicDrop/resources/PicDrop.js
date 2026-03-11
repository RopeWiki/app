/**
 * PicDrop - Drag and drop images into the editor with {{pic}} template insertion
 */
( function ( $, mw ) {
	'use strict';

	var PicDrop = {
		config: null,
		$textarea: null,
		$fileInput: null,
		savedCaretPos: null,
		dragCounter: 0, // Track nested drag events

		/**
		 * Initialize PicDrop
		 */
		init: function () {
			PicDrop.config = mw.config.get( 'picDropConfig' );
			PicDrop.$textarea = $( '#wpTextbox1' );

			if ( !PicDrop.$textarea.length ) {
				return; // No textarea found
			}

			PicDrop.createFileInput();
			PicDrop.attachEventHandlers();
			PicDrop.addToolbarButton();
		},

		/**
		 * Create hidden file input element
		 */
		createFileInput: function () {
			PicDrop.$fileInput = $( '<input>' )
				.attr( {
					type: 'file',
					id: 'picdrop-file-input',
					accept: 'image/*',
					multiple: true,
					style: 'display: none;'
				} )
				.on( 'change', function () {
					var files = this.files;
					if ( files.length > 0 ) {
						// Save cursor position before upload
						PicDrop.savedCaretPos = PicDrop.$textarea.textSelection( 'getCaretPosition' );
						PicDrop.handleFiles( files );
					}
					// Reset input so same file can be selected again
					$( this ).val( '' );
				} );

			// Append to body
			$( 'body' ).append( PicDrop.$fileInput );
		},

		/**
		 * Add upload button to WikiEditor toolbar
		 */
		addToolbarButton: function () {
			// Check if WikiEditor is available
			if ( !$.fn.wikiEditor ) {
				// Fallback: add button near textarea if WikiEditor not available
				PicDrop.addFallbackButton();
				return;
			}

			// Wait for WikiEditor to be ready
			var checkWikiEditor = setInterval( function () {
				if ( $( '#wpTextbox1' ).data( 'wikiEditor-context' ) ) {
					clearInterval( checkWikiEditor );

					$( '#wpTextbox1' ).wikiEditor( 'addToToolbar', {
						section: 'main',
						group: 'insert',
						tools: {
							picDrop: {
								label: 'Upload images',
								type: 'button',
								icon: '/extensions/PicDrop/resources/upload-icon.svg',
								action: {
									type: 'callback',
									execute: function () {
										PicDrop.$fileInput.click();
									}
								}
							}
						}
					} );
				}
			}, 100 );

			// Stop checking after 5 seconds
			setTimeout( function () {
				clearInterval( checkWikiEditor );
			}, 5000 );
		},

		/**
		 * Add fallback button if WikiEditor is not available
		 */
		addFallbackButton: function () {
			var $button = $( '<button>' )
				.attr( {
					type: 'button',
					id: 'picdrop-upload-btn',
					class: 'picdrop-upload-button'
				} )
				.text( '📷 Upload Images' )
				.on( 'click', function ( e ) {
					e.preventDefault();
					PicDrop.$fileInput.click();
				} );

			// Insert button above textarea
			PicDrop.$textarea.before( $button );
		},

		/**
		 * Attach drag-and-drop event handlers to the textarea
		 */
		attachEventHandlers: function () {
			var $textarea = PicDrop.$textarea;

			// Prevent default drag behavior on textarea
			$textarea.on( 'dragover', function ( e ) {
				e.preventDefault();
				e.stopPropagation();
			} );

			// Track when drag enters the textarea
			$textarea.on( 'dragenter', function ( e ) {
				e.preventDefault();
				e.stopPropagation();
				PicDrop.dragCounter++;

				if ( PicDrop.dragCounter === 1 ) {
					$textarea.addClass( 'picdrop-dragover' );
				}
			} );

			// Track when drag leaves the textarea
			$textarea.on( 'dragleave', function ( e ) {
				e.preventDefault();
				e.stopPropagation();
				PicDrop.dragCounter--;

				if ( PicDrop.dragCounter === 0 ) {
					$textarea.removeClass( 'picdrop-dragover' );
				}
			} );

			// Handle the drop event
			$textarea.on( 'drop', function ( e ) {
				e.preventDefault();
				e.stopPropagation();

				PicDrop.dragCounter = 0;
				$textarea.removeClass( 'picdrop-dragover' );

				var files = e.originalEvent.dataTransfer.files;
				if ( files.length > 0 ) {
					// Save cursor position before upload
					PicDrop.savedCaretPos = $textarea.textSelection( 'getCaretPosition' );
					PicDrop.handleFiles( files );
				}
			} );
		},

		/**
		 * Handle dropped files
		 * @param {FileList} files
		 */
		handleFiles: function ( files ) {
			for ( var i = 0; i < files.length; i++ ) {
				var file = files[i];

				// Only process image files
				if ( file.type.match( /^image\// ) ) {
					PicDrop.uploadFile( file );
				} else {
					mw.notify( 'Only image files are supported: ' + file.name, { type: 'error' } );
				}
			}
		},

		/**
		 * Upload a file to MediaWiki
		 * @param {File} file
		 */
		uploadFile: function ( file ) {
			var pageName = PicDrop.config.pageName;
			var originalName = file.name;
			var extension = originalName.substring( originalName.lastIndexOf( '.' ) );
			var baseName = originalName.substring( 0, originalName.lastIndexOf( '.' ) );

			// Clean the base name (remove spaces, special chars)
			baseName = baseName.replace( /\s+/g, '_' ).replace( /[^a-zA-Z0-9_-]/g, '' );

			// Construct the full filename with page name prefix
			var fullFilename = pageName.replace( /\s+/g, '_' ) + '_' + baseName + extension;

			mw.notify( mw.msg( 'picdrop-uploading' ) + ' ' + originalName, { type: 'info' } );

			// Create FormData for upload
			var formData = new FormData();
			formData.append( 'action', 'upload' );
			formData.append( 'format', 'json' );
			formData.append( 'filename', fullFilename );
			formData.append( 'file', file );
			formData.append( 'token', PicDrop.config.editToken );
			formData.append( 'ignorewarnings', '1' ); // Ignore warnings (like file exists)
			formData.append( 'comment', 'Uploaded via PicDrop' );

			// Upload via MediaWiki API
			$.ajax( {
				url: mw.util.wikiScript( 'api' ),
				type: 'POST',
				data: formData,
				processData: false,
				contentType: false,
				success: function ( data ) {
					if ( data.upload && data.upload.result === 'Success' ) {
						PicDrop.onUploadSuccess( baseName + extension, fullFilename );
					} else if ( data.error ) {
						mw.notify( mw.msg( 'picdrop-upload-error' ) + ': ' + data.error.info, { type: 'error' } );
					} else {
						mw.notify( mw.msg( 'picdrop-upload-error' ), { type: 'error' } );
					}
				},
				error: function ( xhr, status, error ) {
					mw.notify( mw.msg( 'picdrop-upload-error' ) + ': ' + error, { type: 'error' } );
				}
			} );
		},

		/**
		 * Handle successful upload - insert {{pic}} template at saved cursor position
		 * @param {string} displayName - The filename without page prefix (for template)
		 * @param {string} fullFilename - The full filename with page prefix
		 */
		onUploadSuccess: function ( displayName, fullFilename ) {
			mw.notify( mw.msg( 'picdrop-upload-success' ) + ': ' + fullFilename, { type: 'success' } );

			// Construct the {{pic}} template with cursor placeholder for description
			var picTemplate = '{{pic|' + displayName + ' ~ }}';

			// Insert at the saved cursor position
			if ( PicDrop.savedCaretPos !== null ) {
				PicDrop.$textarea.textSelection( 'setSelection', {
					start: PicDrop.savedCaretPos,
					end: PicDrop.savedCaretPos
				} );
			}

			PicDrop.$textarea.textSelection( 'encapsulateSelection', {
				pre: picTemplate
			} );

			// Move cursor to description area (between "~ " and "}}")
			var currentPos = PicDrop.$textarea.textSelection( 'getCaretPosition' );
			var newPos = currentPos - 2; // Position before "}}"

			PicDrop.$textarea.textSelection( 'setSelection', {
				start: newPos,
				end: newPos
			} );

			// Focus the textarea
			PicDrop.$textarea.focus();
		}
	};

	// Initialize when document is ready
	$( function () {
		PicDrop.init();
	} );

}( jQuery, mediaWiki ) );
