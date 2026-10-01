#import "RenderProjectionFixture.h"
#include "../Spikes/RenderSnapshot/transport.hpp"

@implementation RenderProjectionFixture
+ (NSString *)project:(NSString *)input {
    std::istringstream source(std::string([input UTF8String]));
    std::ostringstream result;
    projectFixture(source, result);
    return [NSString stringWithUTF8String:result.str().c_str()];
}
@end
