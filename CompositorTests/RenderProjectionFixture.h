#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Hosted-test-only adapter; not an app or renderer API.
@interface RenderProjectionFixture : NSObject
+ (NSString *)project:(NSString *)input;
@end
NS_ASSUME_NONNULL_END
