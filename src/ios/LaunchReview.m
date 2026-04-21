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
        
        UIWindowScene *activeScene = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive &&
                [scene isKindOfClass:[UIWindowScene class]]) {
                activeScene = (UIWindowScene *)scene;
                break;
            }
        }
        
        if (@available(iOS 18.0, *)) {
            if (activeScene) {
                [AppStore requestReviewInScene:activeScene];
            } else {
                [self handlePluginError:@"No active UIWindowScene found for review request" :command.callbackId];
                return;
            }
        } else if (@available(iOS 14.0, *)) {
            if (activeScene && [SKStoreReviewController class]) {
                [SKStoreReviewController requestReviewInScene:activeScene];
            } else if ([SKStoreReviewController class]) {
                [SKStoreReviewController requestReview];
            } else {
                [self handlePluginError:@"Rating dialog requires iOS 10.3+" :command.callbackId];
                return;
            }
        } else if ([SKStoreReviewController class]) {
            [SKStoreReviewController requestReview];
        } else {
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
    NSString* iTunesLink = [NSString stringWithFormat:@"https://apps.apple.com/app/id%@?action=write-review", appId];
    
    NSURL *url = [NSURL URLWithString:iTunesLink];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    } else {
        NSLog(@"LaunchReview: Cannot open URL: %@", url);
    }
    
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                callbackId:self.launchRequestCallbackId];
}

- (void)retrieveAppIdAndLaunch {
    [self fetchAppIdFromBundleId];
    if (self.appStoreId != nil) {
        [self launchAppStore:self.appStoreId];
    }
}

- (void)fetchAppIdFromBundleId {
    if (self.appStoreId != nil) return;
    
    NSString* bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString* urlString = [NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@", bundleId];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                                                             completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !data) {
                if (self.launchRequestCallbackId) {
                    [self handlePluginError:[error localizedDescription] ?: @"Network error fetching App ID" :self.launchRequestCallbackId];
                }
                return;
            }
            
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSArray *results = json[@"results"];
            
            if (results.count > 0) {
                NSDictionary *item = results[0];
                if ([item[@"bundleId"] isEqualToString:bundleId]) {
                    self.appStoreId = [item[@"trackId"] stringValue];
                    if (self.launchRequestCallbackId) {
                        [self launchAppStore:self.appStoreId];
                    }
                    return;
                }
            }
            
            if (self.launchRequestCallbackId) {
                [self handlePluginError:@"The application could not be found on the App Store." :self.launchRequestCallbackId];
            }
        });
    }];
    [task resume];
}

- (void)handlePluginException:(NSException*)exception :(NSString*)callbackId {
    [self handlePluginError:exception.reason :callbackId];
}

- (void)handlePluginError:(NSString*)errorMsg :(NSString*)callbackId {
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                      messageAsString:errorMsg];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}

@end