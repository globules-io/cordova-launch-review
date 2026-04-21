@import UIKit;

#pragma mark - MonitorObject

@interface MonitorObject : NSObject

@property (nonatomic, weak) UIWindow *owner;

- (instancetype)initWithOwner:(UIWindow *)owner;

@end

#pragma mark - UIWindow (DismissNotification)

@interface UIWindow (DismissNotification)

@end