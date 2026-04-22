#import "UIWindow+DismissNotification.h"
#import <objc/runtime.h>

#pragma mark - MonitorObject

@implementation MonitorObject

- (instancetype)initWithOwner:(UIWindow *)owner
{
    self = [super init];
    if (self) {
        self.owner = owner;
        // Notify that the review window became visible
        [[NSNotificationCenter defaultCenter] postNotificationName:UIWindowDidBecomeVisibleNotification
                                                            object:self];
    }
    return self;
}

- (void)dealloc
{
    // Notify that the review window was dismissed/hidden
    [[NSNotificationCenter defaultCenter] postNotificationName:UIWindowDidBecomeHiddenNotification
                                                        object:self];
}

@end

#pragma mark - UIWindow (DismissNotification)

@implementation UIWindow (DismissNotification)

static const void *monitorObjectKey = &monitorObjectKey;
static NSString * const kStoreReviewPartialDesc = @"SKStore";

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(setWindowLevel:);
        SEL swizzledSelector = @selector(setWindowLevel_startMonitor:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        if (!originalMethod || !swizzledMethod) {
            NSLog(@"LaunchReview: Failed to find setWindowLevel: method for swizzling");
            return;
        }
        
        BOOL didAddMethod = class_addMethod(class,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));
        
        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

#pragma mark - Swizzled Method

- (void)setWindowLevel_startMonitor:(NSInteger)level
{
    // Call the original implementation first
    [self setWindowLevel_startMonitor:level];
    
    // Check if this appears to be the Store Review presentation window
    if ([self.description containsString:kStoreReviewPartialDesc]) {
        MonitorObject *monitor = [[MonitorObject alloc] initWithOwner:self];
        objc_setAssociatedObject(self,
                                 monitorObjectKey,
                                 monitor,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@end