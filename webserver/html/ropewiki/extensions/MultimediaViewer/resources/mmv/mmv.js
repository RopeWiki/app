/*
 * This file is part of the MediaWiki extension MultimediaViewer.
 *
 * MultimediaViewer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * MultimediaViewer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with MultimediaViewer.  If not, see <http://www.gnu.org/licenses/>.
 */

( function ( mw, $ ) {
	var MMVP,
		comingFromHashChange = false;

	var imageLoadCount = 0;

	/**
	 * Analyses the page, looks for image content and sets up the hooks
	 * to manage the viewing experience of such content.
	 * @class mw.mmv.MultimediaViewer
	 * @constructor
	 */
	function MultimediaViewer() {
		var apiCacheMaxAge = 86400; // one day

		/**
		 * @property {mw.mmv.provider.Image}
		 * @private
		 */
		this.imageProvider = new mw.mmv.provider.Image();

		/**
		 * @property {mw.mmv.provider.ImageInfo}
		 * @private
		 */
		this.imageInfoProvider = new mw.mmv.provider.ImageInfo( new mw.mmv.logging.Api( 'imageinfo' ),
			// Short-circuit, don't fallback, to save some tiny amount of time
			{ language: mw.config.get( 'wgUserLanguage', false ) || mw.config.get( 'wgContentLanguage', 'en' ) }
		);

		/**
		 * @property {mw.mmv.provider.FileRepoInfo}
		 * @private
		 */
		this.fileRepoInfoProvider = new mw.mmv.provider.FileRepoInfo( new mw.mmv.logging.Api( 'filerepoinfo' ),
			{ maxage: apiCacheMaxAge } );

		/**
		 * @property {mw.mmv.provider.ThumbnailInfo}
		 * @private
		 */
		this.thumbnailInfoProvider = new mw.mmv.provider.ThumbnailInfo( new mw.mmv.logging.Api( 'thumbnailinfo' ),
			{ maxage: apiCacheMaxAge } );

		/**
		 * @property {mw.mmv.provider.ThumbnailInfo}
		 * @private
		 */
		this.guessedThumbnailInfoProvider = new mw.mmv.provider.GuessedThumbnailInfo();

		/**
		 * @property {mw.mmv.provider.UserInfo}
		 * @private
		 */
		this.userInfoProvider = new mw.mmv.provider.UserInfo( new mw.mmv.logging.Api( 'userinfo' ), {
			useApi: this.needGender(),
			maxage: apiCacheMaxAge
		} );

		/**
		 * Image index on page.
		 * @property {number}
		 */
		this.currentIndex = 0;

		/**
		 * @property {mw.mmv.routing.Router} router -
		 */
		this.router = new mw.mmv.routing.Router();

		/**
		 * UI object used to display the pictures in the page.
		 * @property {mw.mmv.LightboxInterface}
		 * @private
		 */
		this.ui = new mw.mmv.LightboxInterface();

		/**
		 * How many sharp images have been displayed in Media Viewer since the pageload
		 * @property {number}
		 */
		this.imageDisplayedCount = 0;

		/**
		 * How many data-filled metadata panels have been displayed in Media Viewer since the pageload
		 * @property {number}
		 */
		this.metadataDisplayedCount = 0;

		/** @property {string} documentTitle base document title, MediaViewer will expand this */
		this.documentTitle = document.title;
	}

	MMVP = MultimediaViewer.prototype;

	/**
	 * Check if we need to fetch gender information. This relies on the fact that
	 * multimediaviewer-userpage-link is the only message which takes a gender parameter.
	 * @return {boolean}
	 * FIXME there has to be a better way than this
	 */
	MMVP.needGender = function () {
		var male, female, unknown;

		male = mw.message( 'multimediaviewer-userpage-link', '_', 'male' ).text();
		female = mw.message( 'multimediaviewer-userpage-link', '_', 'female' ).text();
		unknown = mw.message( 'multimediaviewer-userpage-link', '_', 'unknown' ).text();

		return male !== female || male !== unknown || female !== unknown;
	};

	/**
	 * Initialize the lightbox interface given an array of thumbnail
	 * objects.
	 * @param {Object[]} thumbs Complex structure...TODO, document this better.
	 */
	MMVP.initWithThumbs = function ( thumbs ) {
		var i, thumb;

		this.thumbs = thumbs;

		for ( i = 0; i < this.thumbs.length; i++ ) {
			thumb = this.thumbs[ i ];
			// Create a LightboxImage object for each legit image
			thumb.image = this.createNewImage(
				thumb.$thumb.prop( 'src' ),
				thumb.link,
				thumb.title,
				i,
				thumb.thumb,
				thumb.caption
			);
		}
	};

	/**
	 * Create an image object for the lightbox to use.
	 * @protected
	 * @param {string} fileLink Link to the file - generally a thumb URL
	 * @param {string} filePageLink Link to the File: page
	 * @param {mw.Title} fileTitle Represents the File: page
	 * @param {number} index Which number file this is
	 * @param {HTMLImageElement} thumb The thumbnail that represents this image on the page
	 * @param {string} [caption] The caption, if any.
	 * @returns {mw.mmv.LightboxImage}
	 */
	MMVP.createNewImage = function ( fileLink, filePageLink, fileTitle, index, thumb, caption ) {
		var thisImage = new mw.mmv.LightboxImage( fileLink, filePageLink, fileTitle, index, thumb, caption ),
			$thumb = $( thumb );

		thisImage.filePageLink = filePageLink;
		thisImage.filePageTitle = fileTitle;
		thisImage.index = index;
		thisImage.thumbnail = thumb;
		thisImage.originalWidth = parseInt( $thumb.data( 'file-width' ), 10 );
		thisImage.originalHeight = parseInt( $thumb.data( 'file-height' ), 10 );

		return thisImage;
	};

	/**
	 * Handles resize events in viewer.
	 * @protected
	 * @param {mw.mmv.LightboxInterface} ui lightbox that got resized
	 */
	MMVP.resize = function ( ui ) {
		var viewer = this,
			image = this.thumbs[ this.currentIndex ].image,
			imageWidths;

		this.preloadThumbnails();

		if ( image ) {
			imageWidths = ui.canvas.getCurrentImageWidths();
			this.fetchThumbnailForLightboxImage(
				image, imageWidths.real
			).then( function( thumbnail, image ) {
				viewer.setImage( ui, thumbnail, image, imageWidths );
			}, function ( error ) {
				viewer.ui.canvas.showError( error );
			} );
		}

		this.updateControls();
	};

	/**
	 * Updates positioning of controls, usually after a resize event.
	 */
	MMVP.updateControls = function () {
		var numImages = this.thumbs ? this.thumbs.length : 0,
			showNextButton = this.currentIndex < (numImages - 1),
			showPreviousButton = this.currentIndex > 0;

		this.ui.updateControls( showNextButton, showPreviousButton );
	};

	/**
	 * Loads and sets the specified image. It also updates the controls.
	 * @param {mw.mmv.LightboxInterface} ui image container
	 * @param {mw.mmv.model.Thumbnail} thumbnail thumbnail information
	 * @param {HTMLImageElement} imageElement
	 * @param {mw.mmv.model.ThumbnailWidth} imageWidths
	 */
	MMVP.setImage = function ( ui, thumbnail, imageElement, imageWidths ) {
		ui.canvas.setImageAndMaxDimensions( thumbnail, imageElement, imageWidths );
		this.updateControls();
	};

	/**
	 * Loads a specified image.
	 * @param {mw.mmv.LightboxImage} image
	 * @param {HTMLImageElement} initialImage A thumbnail to use as placeholder while the image loads
	 */
	MMVP.loadImage = function ( image, initialImage ) {
		var imageWidths,
			imagePromise,
			metadataPromise,
			start,
			viewer = this,
			$initialImage = $( initialImage );

		this.currentIndex = image.index;

		this.currentImageFileTitle = image.filePageTitle;

		if ( !this.isOpen ) {
			this.ui.open();
			this.isOpen = true;
			imageLoadCount = 0;
		} else {
			this.ui.empty();
		}
		this.setHash();

		imageLoadCount++;

		// At this point we can't show the thumbnail because we don't
		// know what size it should be. We still assign it to allow for
		// size calculations in getCurrentImageWidths, which needs to know
		// the aspect ratio
		$initialImage.hide();
		this.ui.canvas.set( image, $initialImage );

		this.preloadImagesMetadata();
		this.preloadThumbnails();
		// this.preloadFullscreenThumbnail( image ); // disabled - #474

		imageWidths = this.ui.canvas.getCurrentImageWidths();


		start = $.now();

		imagePromise = this.fetchThumbnailForLightboxImage( image, imageWidths.real );

		this.resetBlurredThumbnailStates();
		if ( imagePromise.state() === 'pending' ) {
			this.displayPlaceholderThumbnail( image, $initialImage, imageWidths );
		}

		this.setupProgressBar( image, imagePromise, imageWidths.real );

		imagePromise.done( function ( thumbnail, imageElement ) {
			if ( viewer.currentIndex !== image.index ) {
				return;
			}

			if ( viewer.imageDisplayedCount++ === 0 ) {
				mw.mmv.durationLogger.stop( 'click-to-first-image' );
			}
			viewer.displayRealThumbnail( thumbnail, imageElement, imageWidths, $.now() - start );
		} ).fail( function ( error ) {
			viewer.ui.canvas.showError( error );
		} );

		metadataPromise = this.fetchSizeIndependentLightboxInfo(
			image.filePageTitle
		).done( function ( imageInfo, repoInfo, userInfo ) {
			if ( viewer.currentIndex !== image.index ) {
				return;
			}

			if ( viewer.metadataDisplayedCount++ === 0 ) {
				mw.mmv.durationLogger.stop( 'click-to-first-metadata' );
			}
			viewer.ui.panel.setImageInfo( image, imageInfo, repoInfo, userInfo );

			// File reuse steals a bunch of information from the DOM, so do it last
			viewer.ui.setFileReuseData( imageInfo, repoInfo, image.caption );
		} ).fail( function ( error ) {
			if ( viewer.currentIndex !== image.index ) {
				return;
			}

			viewer.ui.panel.showError( error );
		} );

		$.when( imagePromise, metadataPromise ).then( function() {
			if ( viewer.currentIndex !== image.index ) {
				return;
			}

			viewer.ui.panel.scroller.animateMetadataOnce();
			viewer.preloadDependencies();
		} );

		this.comingFromHashChange = false;
	};

	/**
	 * Loads an image by its title
	 * @param {mw.Title} title
	 * @param {boolean} updateHash Viewer should update the location hash when true
	 */
	MMVP.loadImageByTitle = function ( title, updateHash ) {
		var viewer = this;

		if ( !this.thumbs || !this.thumbs.length ) {
			return;
		}

		this.comingFromHashChange = !updateHash;

		$.each( this.thumbs, function ( idx, thumb ) {
			if ( thumb.title.getPrefixedText() === title.getPrefixedText() ) {
				viewer.loadImage( thumb.image, thumb.$thumb.clone()[ 0 ], true );
				return false;
			}
		} );
	};

	/**
	 * @private
	 * Image loading progress. Keyed by image (database) name + '|' + thumbnail width in pixels,
	 * value is undefined, 'blurred' or 'real' (meaning respectively that no thumbnail is shown
	 * yet / the thumbnail that existed on the page is shown, enlarged and blurred / the real,
	 * correct-size thumbnail is shown).
	 * @property {Object.<string, string>}
	 */
	MMVP.thumbnailStateCache = {};

	/**
	 * Resets the cross-request states needed to handle the blurred thumbnail logic.
	 */
	MMVP.resetBlurredThumbnailStates = function () {
		/**
		 * Stores whether the real image was loaded and displayed already.
		 * This is reset when paging, so it is not necessarily accurate.
		 * @property {boolean}
		 */
		this.realThumbnailShown = false;

		/**
		 * Stores whether the a blurred placeholder is being displayed in place of the real image.
		 * When a placeholder is displayed, but it is not blurred, this is false.
		 * This is reset when paging, so it is not necessarily accurate.
		 * @property {boolean}
		 */
		this.blurredThumbnailShown = false;
	};

	/**
	 * Display the real, full-resolution, thumbnail that was fetched with fetchThumbnail
	 * @param {mw.mmv.model.Thumbnail} thumbnail
	 * @param {HTMLImageElement} imageElement
	 * @param {mw.mmv.model.ThumbnailWidth} imageWidths
	 * @param {number} loadTime Time it took to load the thumbnail
	 */
	MMVP.displayRealThumbnail = function ( thumbnail, imageElement, imageWidths, loadTime ) {
		this.realThumbnailShown = true;

		this.setImage( this.ui, thumbnail, imageElement, imageWidths );

		// We only animate unblurWithAnimation if the image wasn't loaded from the cache
		// A load in < 10ms is considered to be a browser cache hit
		if ( this.blurredThumbnailShown && loadTime > 10 ) {
			this.ui.canvas.unblurWithAnimation();
		} else {
			this.ui.canvas.unblur();
		}

		mw.mmv.actionLogger.log( 'image-view' );
	};

	/**
	 * Display the blurred thumbnail from the page
	 * @param {mw.mmv.LightboxImage} image
	 * @param {jQuery} $initialImage The thumbnail from the page
	 * @param {mw.mmv.model.ThumbnailWidth} imageWidths
	 * @param {boolean} [recursion=false] for internal use, never set this when calling from outside
	 */
	MMVP.displayPlaceholderThumbnail = function ( image, $initialImage, imageWidths, recursion ) {
		var viewer = this,
			size = { width : image.originalWidth, height : image.originalHeight };

		// If the actual image has already been displayed, there's no point showing the blurry one.
		// This can happen if the API request to get the original image size needed to show the
		// placeholder thumbnail takes longer then loading the actual thumbnail.
		if ( this.realThumbnailShown ) {
			return;
		}

		// Width/height of the original image are added to the HTML by MediaViewer via a PHP hook,
		// and can be missing in exotic circumstances, e. g. when the extension has only been
		// enabled recently and the HTML cache has not cleared yet. If that is the case, we need
		// to fetch the size from the API first.
		if ( !size.width || !size.height ) {
			if ( recursion ) {
				// this should not be possible, but an infinite recursion is nasty
				// business, so we make a sanity check
				throw 'MediaViewer internal error: displayPlaceholderThumbnail recursion';
			}
			this.imageInfoProvider.get( image.filePageTitle ).done( function ( imageInfo ) {
				// Make sure the user has not navigated away while we were waiting for the size
				if ( viewer.currentIndex === image.index ) {
					image.originalWidth = imageInfo.width;
					image.originalHeight = imageInfo.height;
					viewer.displayPlaceholderThumbnail( image, $initialImage, imageWidths, true );
				}
			} );
		} else {
			this.blurredThumbnailShown = this.ui.canvas.maybeDisplayPlaceholder(
				size, $initialImage, imageWidths );
		}
	};

	/**
	 * @private
	 * Image loading progress. Keyed by image (database) name + '|' + thumbnail width in pixels,
	 * value is a number between 0-100.
	 * @property {Object.<string, number>}
	 */
	MMVP.progressCache = {};

	/**
	 * Displays a progress bar for the image loading, if necessary, and sets up handling of
	 * all the related callbacks.
	 * @param {mw.mmv.LightboxImage} image
	 * @param {jQuery.Promise.<mw.mmv.model.Thumbnail, HTMLImageElement>} imagePromise
	 * @param {number} imageWidth needed for caching progress (FIXME)
	 */
	MMVP.setupProgressBar = function ( image, imagePromise, imageWidth ) {
		var viewer = this,
			progressBar = viewer.ui.panel.progressBar,
			key = image.filePageTitle.getPrefixedDb() + '|' + imageWidth;

		if ( imagePromise.state() !== 'pending' ) {
			// image has already loaded (or failed to load) - do not show the progress bar
			progressBar.hide();
			return;
		}

		if ( !this.progressCache[key] ) {
			// Animate progress bar to 5 to give a sense that something is happening, and make sure
			// the progress bar is noticeable, even if we're sitting at 0% stuck waiting for
			// server-side processing, such as thumbnail (re)generation
			progressBar.jumpTo( 0 );
			progressBar.animateTo( 5 );
			viewer.progressCache[key] = 5;
		} else {
			progressBar.jumpTo( this.progressCache[key] );
		}

		// FIXME would be nice to have a "filtered" promise which does not fire when the image is not visible
		imagePromise.progress( function ( progress ) {
			// We pretend progress is always at least 5%, so progress events below 5% should be ignored
			// 100 will be handled by the done handler, do not mix two animations
			if ( progress < 5 || progress === 100 ) {
				return;
			}

			viewer.progressCache[key] = progress;

			// Touch the UI only if the user is looking at this image
			if ( viewer.currentIndex === image.index ) {
				progressBar.animateTo( progress );
			}
		} ).done( function () {
			viewer.progressCache[key] = 100;

			if ( viewer.currentIndex === image.index ) {
				// Fallback in case the browser doesn't have fancy progress updates
				progressBar.animateTo( 100 );
			}
		} ).fail( function () {
			viewer.progressCache[key] = 100;

			if ( viewer.currentIndex === image.index ) {
				// Hide progress bar on error
				progressBar.hide();
			}
		} );
	};

	/**
	 * Preload this many prev/next images to speed up navigation.
	 * (E.g. preloadDistance = 3 means that the previous 3 and the next 3 images will be loaded.)
	 * Preloading only happens when the viewer is open.
	 * @property {number}
	 */
	MMVP.preloadDistance = 1;

	/**
	 * Stores image metadata preloads, so they can be cancelled.
	 * @property {mw.mmv.model.TaskQueue}
	 */
	MMVP.metadataPreloadQueue = null;

	/**
	 * Stores image thumbnail preloads, so they can be cancelled.
	 * @property {mw.mmv.model.TaskQueue}
	 */
	MMVP.thumbnailPreloadQueue = null;

	/**
	 * Orders lightboximage indexes for preloading. Works similar to $.each, except it only takes
	 * the callback argument. Calls the callback with each lightboximage index in some sequence
	 * that is ideal for preloading.
	 * @private
	 * @param {function(number, mw.mmv.LightboxImage)} callback
	 */
	MMVP.eachPrealoadableLightboxIndex = function( callback ) {
		for ( var i = 0; i <= this.preloadDistance; i++ ) {
			if ( this.currentIndex + i < this.thumbs.length ) {
				callback(
					this.currentIndex + i,
					this.thumbs[ this.currentIndex + i ].image
				);
			}
			if ( i && this.currentIndex - i >= 0 ) { // skip duplicate for i==0
				callback(
					this.currentIndex - i,
					this.thumbs[ this.currentIndex - i ].image
				);
			}
		}
	};

	/**
	 * A helper function to fill up the preload queues.
	 * taskFactory(lightboxImage) should return a preload task for the given lightboximage.
	 * @private
	 * @param {function(mw.mmv.LightboxImage): function()} taskFactory
	 * @return {mw.mmv.model.TaskQueue}
	 */
	MMVP.pushLightboxImagesIntoQueue = function( taskFactory ) {
		var queue = new mw.mmv.model.TaskQueue();

		this.eachPrealoadableLightboxIndex( function( i, lightboxImage ) {
			queue.push( taskFactory( lightboxImage ) );
		} );

		return queue;
	};

	/**
	 * Cancels in-progress image metadata preloading.
	 */
	MMVP.cancelImageMetadataPreloading = function() {
		if ( this.metadataPreloadQueue ) {
			this.metadataPreloadQueue.cancel();
		}
	};

	/**
	 * Cancels in-progress image thumbnail preloading.
	 */
	MMVP.cancelThumbnailsPreloading = function() {
		if ( this.thumbnailPreloadQueue ) {
			this.thumbnailPreloadQueue.cancel();
		}
	};

	/**
	 * Preload metadata for next and prev N image (N = MMVP.preloadDistance).
	 * Two images will be loaded at a time (one forward, one backward), with closer images
	 * being loaded sooner.
	 */
	MMVP.preloadImagesMetadata = function() {
		var viewer = this;

		this.cancelImageMetadataPreloading();

		this.metadataPreloadQueue = this.pushLightboxImagesIntoQueue( function( lightboxImage ) {
			return function() {
				return viewer.fetchSizeIndependentLightboxInfo( lightboxImage.filePageTitle );
			};
		} );

		this.metadataPreloadQueue.execute();
	};

	/**
	 * Preload thumbnails for next and prev N image (N = MMVP.preloadDistance).
	 * Two images will be loaded at a time (one forward, one backward), with closer images
	 * being loaded sooner.
	 */
	MMVP.preloadThumbnails = function() {
		var viewer = this;

		this.cancelThumbnailsPreloading();

		this.thumbnailPreloadQueue = this.pushLightboxImagesIntoQueue( function( lightboxImage ) {
			return function() {
				// viewer.ui.canvas.getLightboxImageWidths needs the viewer to be open
				// because it needs to read the size of visible elements
				if ( !viewer.isOpen ) {
					return;
				}

				return viewer.fetchThumbnailForLightboxImage(
					lightboxImage,
					viewer.ui.canvas.getLightboxImageWidths( lightboxImage ).real
				);
			};
		} );

		this.thumbnailPreloadQueue.execute();
	};

	/**
	 * Preload the fullscreen size of the current image.
	 */
	MMVP.preloadFullscreenThumbnail = function( image ) {
		this.fetchThumbnailForLightboxImage(
			image,
			this.ui.canvas.getLightboxImageWidthsForFullscreen( image ).real
		);
	};

	/**
	 * Loads all the size-independent information needed by the lightbox (image metadata, repo
	 * information, uploader data).
	 * @param {mw.Title} fileTitle Title of the file page for the image.
	 * @returns {jQuery.Promise.<mw.mmv.model.Image, mw.mmv.model.Repo, mw.mmv.model.User>}
	 */
	MMVP.fetchSizeIndependentLightboxInfo = function ( fileTitle ) {
		var viewer = this,
			imageInfoPromise = this.imageInfoProvider.get( fileTitle ),
			repoInfoPromise = this.fileRepoInfoProvider.get( fileTitle ),
			userInfoPromise;

		userInfoPromise = $.when(
			imageInfoPromise, repoInfoPromise
		).then( function( imageInfo, repoInfoHash ) {
			if ( imageInfo.lastUploader ) {
				return viewer.userInfoProvider.get( imageInfo.lastUploader, repoInfoHash[imageInfo.repo] );
			} else {
				return null;
			}
		} );

		return $.when(
			imageInfoPromise, repoInfoPromise, userInfoPromise
		).then( function( imageInfo, repoInfoHash, userInfo ) {
			return $.Deferred().resolve( imageInfo, repoInfoHash[imageInfo.repo], userInfo );
		} );
	};

	/**
	 * Loads size-dependent components of a lightbox - the thumbnail model and the image itself.
	 * @param {mw.mmv.LightboxImage} image
	 * @param {number} width the width of the requested thumbnail
	 * @returns {jQuery.Promise.<mw.mmv.model.Thumbnail, HTMLImageElement>}
	 */
	MMVP.fetchThumbnailForLightboxImage = function ( image, width ) {
		return this.fetchThumbnail(
			image.filePageTitle,
			width,
			image.src,
			image.originalWidth,
			image.originalHeight
		);
	};

	/**
	 * Loads size-dependent components of a lightbox - the thumbnail model and the image itself.
	 * @param {mw.Title} fileTitle
	 * @param {number} width the width of the requested thumbnail
	 * @param {string} [sampleUrl] a thumbnail URL for the same file (but with different size) (might be missing)
	 * @param {number} [originalWidth] the width of the original, full-sized file (might be missing)
	 * @param {number} [originalHeight] the height of the original, full-sized file (might be missing)
	 * @returns {jQuery.Promise.<mw.mmv.model.Thumbnail, HTMLImageElement>} A promise resolving to
	 *  a thumbnail model and an <img> element. It might or might not have progress events which
	 *  return a single number.
	 */
	MMVP.fetchThumbnail = function ( fileTitle, width, sampleUrl, originalWidth, originalHeight ) {
		var viewer = this,
			guessing = false,
			thumbnailPromise,
			imagePromise;

		if ( originalWidth && width > originalWidth ) {
			// Do not request images larger than the original image
			// This would be possible (but still unwanted) for SVG images
			width = originalWidth;
		}

		if (
			sampleUrl && originalWidth && originalHeight &&
			mw.config.get( 'wgMultimediaViewer' ).useThumbnailGuessing
		) {
			guessing = true;
			thumbnailPromise = this.guessedThumbnailInfoProvider.get(
				fileTitle, sampleUrl, width, originalWidth, originalHeight
			).then( null, function () { // catch rejection, use fallback
					return viewer.thumbnailInfoProvider.get( fileTitle, width );
			} );
		} else {
			thumbnailPromise = this.thumbnailInfoProvider.get( fileTitle, width );
		}

		imagePromise = thumbnailPromise.then( function ( thumbnail ) {
			return viewer.imageProvider.get( thumbnail.url );
		} );

		if ( guessing ) {
			// If we guessed wrong, need to retry with real URL on failure.
			// As a side effect this introduces an extra (harmless) retry of a failed thumbnailInfoProvider.get call
			// because thumbnailInfoProvider.get is already called above when guessedThumbnailInfoProvider.get fails.
			imagePromise = imagePromise.then( null, function () {
				return viewer.thumbnailInfoProvider.get( fileTitle, width ).then( function ( thumbnail ) {
					return viewer.imageProvider.get( thumbnail.url );
				} );
			} );
		}

		return $.when( thumbnailPromise, imagePromise ).then( null, null, function ( thumbnailProgress, imageProgress ) {
			// Make progress events have a nice format.
			return imageProgress[1];
		} );
	};

	/**
	 * Loads an image at a specified index in the viewer's thumbnail array.
	 * @param {number} index
	 */
	MMVP.loadIndex = function ( index ) {
		var thumb;

		if ( index < this.thumbs.length && index >= 0 ) {
			thumb = this.thumbs[ index ];
			this.loadImage( thumb.image, thumb.$thumb.clone()[0] );
		}
	};

	/**
	 * Opens the next image
	 */
	MMVP.nextImage = function () {
		mw.mmv.actionLogger.log( 'next-image' );
		this.loadIndex( this.currentIndex + 1 );
	};

	/**
	 * Opens the previous image
	 */
	MMVP.prevImage = function () {
		mw.mmv.actionLogger.log( 'prev-image' );
		this.loadIndex( this.currentIndex - 1 );
	};

	/**
	 * Handles close event coming from the lightbox
	 */
	MMVP.close = function () {
		var windowTitle = this.createDocumentTitle( null );

		if ( comingFromHashChange === false ) {
			window.history.go(-imageLoadCount);
			imageLoadCount = 0;
		} else {
			comingFromHashChange = false;
		}

		// This has to happen after the hash reset, because setting the hash to # will reset the page scroll
		$( document ).trigger( $.Event( 'mmv-cleanup-overlay' ) );

		this.isOpen = false;
	};

	/**
	 * Handles a hash change coming from the browser
	 */
	MMVP.hash = function () {
		var route = this.router.parseLocation( window.location );

		if ( route instanceof mw.mmv.routing.ThumbnailRoute ) {
			document.title = this.createDocumentTitle( route.fileTitle );
			this.loadImageByTitle( route.fileTitle );
		} else if ( this.isOpen ) {
			// This allows us to avoid the mmv-hash event that normally happens on close
			comingFromHashChange = true;

			document.title = this.createDocumentTitle( null );
			if ( this.ui ) {
				// FIXME triggers mmv-close event, which calls viewer.close()
				this.ui.unattach();
			} else {
				this.close();
			}
		}
	};

	MMVP.setHash = function() {
		var route, windowTitle, hashFragment;
		if ( !this.comingFromHashChange ) {
			route = new mw.mmv.routing.ThumbnailRoute( this.currentImageFileTitle );
			hashFragment = '#' + this.router.createHash( route );
			windowTitle = this.createDocumentTitle( this.currentImageFileTitle );
			$( document ).trigger( $.Event( 'mmv-hash', { hash : hashFragment, title: windowTitle } ) );
		}
	};

	/**
	 * Creates a string which can be shown as document title (the text at the top of the browser window).
	 * @param {mw.Title|null} imageTitle the title object for the image which is displayed; null when the
	 *  viewer is being closed
	 * @return {string}
	 */
	MMVP.createDocumentTitle = function ( imageTitle ) {
		if ( imageTitle ) {
			return imageTitle.getNameText() + ' - ' + this.documentTitle;
		} else {
			return this.documentTitle;
		}
	};

	/**
	 * @event mmv-close
	 * Fired when the viewer is closed. This is used by the ligthbox to notify the main app.
	 */
	/**
	 * @event mmv-next
	 * Fired when the user requests the next image.
	 */
	/**
	 * @event mmv-prev
	 * Fired when the user requests the previous image.
	 */
	/**
	 * @event mmv-resize
	 * Fired when the screen size changes.
	 */
	/**
	 * @event mmv-request-thumbnail
	 * Used by components to request a thumbnail URL for the current thumbnail, with a given size.
	 * @param {number} size
	 */
	/**
	 * Registers all event handlers
	 */
	MMVP.setupEventHandlers = function () {
		var viewer = this;

		$( document ).on( 'mmv-close.mmvp', function () {
			viewer.close();
		} ).on( 'mmv-next.mmvp', function () {
			viewer.nextImage();
		} ).on( 'mmv-prev.mmvp', function () {
			viewer.prevImage();
		} ).on( 'mmv-resize.mmvp', function () {
			viewer.resize( viewer.ui );
		} ).on( 'mmv-request-thumbnail.mmvp', function ( e, size ) {
			if ( viewer.currentImageFileTitle ) {
				return viewer.thumbnailInfoProvider.get( viewer.currentImageFileTitle, size );
			} else {
				return $.Deferred().reject();
			}
		} ).on( 'mmv-viewfile.mmvp', function () {
			viewer.imageInfoProvider.get( viewer.currentImageFileTitle ).done( function ( imageInfo ) {
				document.location = imageInfo.url;
			} );
		} );
	};

	/**
	* Unregisters all event handlers. Currently only used in tests.
	*/
	MMVP.cleanupEventHandlers = function () {
		$( document ).off( 'mmv-close.mmvp mmv-next.mmvp mmv-prev.mmvp mmv-resize.mmvp' );
	};

	/**
	 * Preloads JS and CSS dependencies that aren't needed to display the first image, but could be needed later
	 */
	MMVP.preloadDependencies = function () {
		mw.loader.load( [ 'mmv.ui.reuse.share', 'mmv.ui.reuse.embed', 'mmv.ui.reuse.download', 'moment' ] );
	};

	mw.mmv.MultimediaViewer = MultimediaViewer;
}( mediaWiki, jQuery ) );
