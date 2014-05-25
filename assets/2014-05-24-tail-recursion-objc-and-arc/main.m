//
//  Created by Jonathon Mah on 2014-05-24.
//  Released into the public domain.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>


@interface ListNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) ListNode *next;
- (NSUInteger)length_v1;
- (NSUInteger)length_v2;
- (NSUInteger)length_v3;
- (NSUInteger)length_v4;
- (NSUInteger)length_v5;
- (NSUInteger)length_v6;
- (NSUInteger)length_v7;
- (NSUInteger)length_v8;
@end


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSArray *names = @[@"Jack", @"Jill", @"Alice", @"Bob", @"Eve"];
        ListNode *head = nil;
        for (NSUInteger i = 0; i < 10; i++) {
            ListNode *ln = [ListNode new];
            ln.name = names[arc4random_uniform((uint32_t)names.count)];
            ln.next = head;
            head = ln;
        }

        NSLog(@"length: %lu", head.length_v1);
        NSLog(@"length: %lu", head.length_v2);
        NSLog(@"length: %lu", head.length_v3);
        NSLog(@"length: %lu", head.length_v4);
        NSLog(@"length: %lu", head.length_v5);
        NSLog(@"length: %lu", head.length_v6);
        NSLog(@"length: %lu", head.length_v7);
        NSLog(@"length: %lu", head.length_v8);
    }
    return 0;
}



@implementation ListNode
- (NSUInteger)length_v1 {
    return 1 + [self.next length_v1];
}

- (NSUInteger)length_v2 {
    return [[self class] lengthOfListWithHead_v2:self];
}
+ (NSUInteger)lengthOfListWithHead_v2:(ListNode *)node {
    if (!node)
        return 0; // base case
    else
        return 1 + [self lengthOfListWithHead_v2:node.next];
}

- (NSUInteger)length_v3 {
    return [[self class] lengthOfListWithHead_v3:self];
}
+ (NSUInteger)lengthOfListWithHead_v3:(ListNode *)node {
    NSUInteger count = 0;
    while (node) {
        count += 1;
        node = node.next;
    }
    return count;
}

- (NSUInteger)length_v4 {
    return [[self class] lengthOfListWithHead_v4:self count:0];
}
+ (NSUInteger)lengthOfListWithHead_v4:(ListNode *)node count:(NSUInteger)count {
    while (node) {
        count += 1;
        node = node.next;
    }
    return count;
}

- (NSUInteger)length_v5 {
    return [[self class] lengthOfListWithHead_v5:self count:0];
}
+ (NSUInteger)lengthOfListWithHead_v5:(ListNode *)node count:(NSUInteger)count {
top:
    if (!node) {
        return count;
    } else {
        count += 1;
        node = node.next;
        goto top;
    }
}

- (NSUInteger)length_v6 {
    return [[self class] lengthOfListWithHead_v6:self count:0];
}
+ (NSUInteger)lengthOfListWithHead_v6:(ListNode *)node count:(NSUInteger)count {
    if (!node)
        return count;
    else {
        return [self lengthOfListWithHead_v6:node.next count:(count + 1)];
    }
}

- (NSUInteger)length_v7 {
    return [[self class] lengthOfListWithHead_v7:self count:0];
}
+ (NSUInteger)lengthOfListWithHead_v7:(ListNode *)node count:(NSUInteger)count {
    if (!node)
        return count;
    else
        return [self lengthOfListWithHead_v7:node->_next count:(count + 1)];
}

- (NSUInteger)length_v8 {
    return [[self class] lengthOfListWithHead_v8:self count:0];
}
+ (NSUInteger)lengthOfListWithHead_v8:(ListNode *)node count:(NSUInteger)count {
    if (!node)
        return count;
    else if (object_getClass(node) == self)
        return [self lengthOfListWithHead_v8:node->_next count:(count + 1)];
    else
        return [self lengthOfListWithHead_v8:node.next count:(count + 1)];
}
@end
