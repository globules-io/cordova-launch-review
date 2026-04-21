/* Copyright (c) 2015 Dave Alden  (http://github.com/dpa99c)
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 *
 */
var exec = require('cordova/exec');

var LaunchReview = {
     /**
      * Check if the current platform and OS version supports in-app rating prompts.
      * @returns {boolean}
      */
     isRatingSupported: function () {
          var deviceVersion = window.device && window.device.version ? parseFloat(window.device.version) : 0;
          return deviceVersion >= 10.3 || (cordova.platformId === 'ios' && deviceVersion === 0); // fallback if device plugin not present
     },

     /**
      * Request the in-app rating dialog (iOS) or Play Store review flow (Android).
      * On success, returns "requested". The "shown" / "dismissed" events are unreliable.
      *
      * @param {function} successCallback - called with status string ("requested", "shown", "dismissed")
      * @param {function} errorCallback   - called on error
      */
     rating: function (successCallback, errorCallback) {
          if (!this.isRatingSupported()) {
               if (errorCallback) errorCallback('Rating dialog requires iOS 10.3+ or equivalent Android support');
               return;
          }

          exec(successCallback, errorCallback, 'LaunchReview', 'rating', []);
     },

     /**
      * Launch the App Store write-review page for the current app (or specified appId).
      *
      * @param {string} [appId]          - optional App Store ID. If omitted, plugin attempts to detect it.
      * @param {function} successCallback
      * @param {function} errorCallback
      */
     launch: function (appId, successCallback, errorCallback) {
          // Support both old signature (no appId) and new (with appId)
          if (typeof appId === 'function') {
               errorCallback = successCallback;
               successCallback = appId;
               appId = null;
          }

          exec(successCallback, errorCallback, 'LaunchReview', 'launch', [appId || null]);
     },
};

module.exports = LaunchReview;
