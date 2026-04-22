/*
 * Copyright (c) 2015 Dave Alden (http://github.com/dpa99c)
 * Updated 2026 for iOS 26 compatibility by Grok
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
 */
#import "LaunchReview.h"
#import <StoreKit/StoreKit.h>
#import "UIWindow+DismissNotification.h"

@implementation LaunchReview

- (void)pluginInitialize {
    [super pluginInitialize];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidBecomeVisibleNotification:)
                                                 name:UIWindowDidBecomeVisibleNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidBecomeHiddenNotification:)
                                                 name:UIWindowDidBecomeHiddenNotification
                                               object:nil];
    
    self.appStoreId = nil;
    self.launchRequestCallbackId = nil;
    self.ratingRequestCallbackId = nil;
    
    // Pre-fetch App ID in background
    [self.commandDelegate runInBackground:^{
        [self fetchAppIdFromBundleId];
    }];
}

- (void)launch:(CDVInvokedUrlCommand*)command {
    @try {
        self.launchRequestCallbackId = command.callbackId;
        
        NSString* appId = [command.arguments objectAtIndex:0];
        if ([self isNull:appId]) {
            [self retrieveAppIdAndLaunch];
        } else {
            [self launchAppStore:appId];
        }
    }
    @catch (NSException *exception) {
        [self handlePluginException:exception :command.callbackId];
    }
}

- (void)rating:(CDVInvokedUrlCommand*)command {
    @try {
        self.ratingRequestCallbackId = command.callbackId;

        BOOL didRequest = NO;

        // Scene-based request only on iOS 13+ (connectedScenes API)
        if (@available(iOS 13.0, *)) {
            UIWindowScene *activeScene = nil;
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive &&
                    [scene isKindOfClass:[UIWindowScene class]]) {
                    activeScene = (UIWindowScene *)scene;
                    break;
                }
            }

            if (activeScene && @available(iOS 14.0, *)) {
                [SKStoreReviewController requestReviewInScene:activeScene];
                didRequest = YES;
            }
        }

        // Legacy fallback for iOS 10.3 - 13.x
        if (!didRequest && [SKStoreReviewController class]) {
            [SKStoreReviewController requestReview];
        }
        else if (![SKStoreReviewController class]) {
            [self handlePluginError:@"Rating dialog requires iOS 10.3+" :command.callbackId];
            return;
        }

        // Always send "requested" immediately (Apple does not guarantee the prompt will appear)
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                          messageAsString:@"requested"];
        [pluginResult setKeepCallback:@YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
    @catch (NSException *exception) {
        [self handlePluginException:exception :command.callbackId];
    }
}

- (void)windowDidBecomeVisibleNotification:(NSNotification *)notification {
    @try {
        NSString* className = NSStringFromClass([notification.object class]);
        if ([notification.object class] == [MonitorObject class] ||
            [className isEqualToString:@"SKStoreReviewPresentationWindow"]) {
            
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                              messageAsString:@"shown"];
            [pluginResult setKeepCallback:@YES];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.ratingRequestCallbackId];
        }
    }
    @catch (NSException *exception) {
        [self handlePluginException:exception :self.ratingRequestCallbackId];
    }
}

- (void)windowDidBecomeHiddenNotification:(NSNotification *)notification {
    @try {
        NSString* className = NSStringFromClass([notification.object class]);
        if ([notification.object class] == [MonitorObject class] ||
            [className isEqualToString:@"SKStoreReviewPresentationWindow"]) {
            
            CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                              messageAsString:@"dismissed"];
            [pluginResult setKeepCallback:@NO];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:self.ratingRequestCallbackId];
        }
    }
    @catch (NSException *exception) {
        [self handlePluginException:exception :self.ratingRequestCallbackId];
    }
}

- (BOOL)isNull:(NSString*)string {
    return string == nil || string == (id)[NSNull null];
}

- (void)launchAppStore:(NSString*)appId {
    if ([self isNull:appId]) {
        [self handlePluginError:@"App ID is required to launch the App Store" :self.launchRequestCallbackId];
        return;
    }

    NSString* iTunesLink = [NSString stringWithFormat:@"https://apps.apple.com/app/id%@?action=write-review", appId];
    NSURL *url = [NSURL URLWithString:iTunesLink];

    if (![[UIApplication sharedApplication] canOpenURL:url]) {
        [self handlePluginError:[NSString stringWithFormat:@"Cannot open App Store URL: %@", url]
                   :self.launchRequestCallbackId];
        return;
    }

    // Open asynchronously and report success/failure back to JavaScript
    [[UIApplication sharedApplication] openURL:url
                                       options:@{}
                             completionHandler:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:self.launchRequestCallbackId];
            } else {
                [self handlePluginError:[NSString stringWithFormat:@"Failed to open App Store URL: %@", url]
                           :self.launchRequestCallbackId];
            }
        });
    }];
}

- (void)retrieveAppIdAndLaunch {
    [self fetchAppIdFromBundleId];
    // Note: launchAppStore will be called from inside fetchAppIdFromBundleId if successful
}

- (void)fetchAppIdFromBundleId {
    if (self.appStoreId != nil) return;

    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    if ([self isNull:bundleId]) {
        if (self.launchRequestCallbackId) {
            [self handlePluginError:@"Could not determine bundle identifier" :self.launchRequestCallbackId];
        }
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@", bundleId];
    NSURL *url = [NSURL URLWithString:urlString];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !data) {
                if (self.launchRequestCallbackId) {
                    NSString *msg = error ? [error localizedDescription] : @"Network error fetching App ID";
                    [self handlePluginError:msg :self.launchRequestCallbackId];
                }
                return;
            }

            // Safe JSON parsing with validation
            NSError *jsonError = nil;
            id jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

            if (jsonError || ![jsonObject isKindOfClass:[NSDictionary class]]) {
                if (self.launchRequestCallbackId) {
                    [self handlePluginError:@"Failed to parse App Store lookup response" :self.launchRequestCallbackId];
                }
                return;
            }

            NSDictionary *json = (NSDictionary *)jsonObject;
            NSArray *results = json[@"results"];

            if (![results isKindOfClass:[NSArray class]] || results.count == 0) {
                if (self.launchRequestCallbackId) {
                    [self handlePluginError:@"The application could not be found on the App Store." :self.launchRequestCallbackId];
                }
                return;
            }

            id firstResult = results[0];
            if (![firstResult isKindOfClass:[NSDictionary class]]) {
                if (self.launchRequestCallbackId) {
                    [self handlePluginError:@"Invalid response format from App Store" :self.launchRequestCallbackId];
                }
                return;
            }

            NSDictionary *item = (NSDictionary *)firstResult;

            // Validate bundle ID matches
            NSString *responseBundleId = item[@"bundleId"];
            if (![responseBundleId isKindOfClass:[NSString class]] || 
                ![responseBundleId isEqualToString:bundleId]) {
                if (self.launchRequestCallbackId) {
                    [self handlePluginError:@"The application could not be found on the App Store." :self.launchRequestCallbackId];
                }
                return;
            }

            // Safely extract trackId
            id trackIdValue = item[@"trackId"];
            NSString *trackId = nil;

            if ([trackIdValue isKindOfClass:[NSNumber class]]) {
                trackId = [(NSNumber *)trackIdValue stringValue];
            } else if ([trackIdValue isKindOfClass:[NSString class]]) {
                trackId = (NSString *)trackIdValue;
            }

            if ([self isNull:trackId]) {
                if (self.launchRequestCallbackId) {
                    [self handlePluginError:@"Could not extract App Store ID from response" :self.launchRequestCallbackId];
                }
                return;
            }

            self.appStoreId = trackId;

            // If a launch was pending, proceed
            if (self.launchRequestCallbackId) {
                [self launchAppStore:self.appStoreId];
            }
        });
    }];

    [task resume];
}

- (void)handlePluginException:(NSException*)exception :(NSString*)callbackId {
    [self handlePluginError:exception.reason :callbackId];
}

- (void)handlePluginError:(NSString*)errorMsg :(NSString*)callbackId {
    if (!callbackId) return;
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:errorMsg];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

@end