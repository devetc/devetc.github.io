---
layout: post
title: "Tail Recursion, Objective-C, and ARC"
date: 2014-05-24 23:26:15 -0700
categories: code
tags: cocoa
subtitle: A tale of conflicting optimizations.
---

Tail recursion is a way to perform recursion without using a stack frame.
Put another way, tail recursion is writing iterative loops using recursive syntax.

For a contrived but simple example, consider a linked list definition, with a method to calculate the length:

{% highlight objc %}
@interface ListNode : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) ListNode *next;
- (NSUInteger)length;
@end
{% endhighlight %}

A simple, recursive implementation of `-length` could be:

{% highlight objc %}
// v1
- (NSUInteger)length {
    return 1 + [self.next length];
}
{% endhighlight %}

This exploits the fact that calls to `nil` will return zero[^send-to-nil], which happens to work in this specific case because the base case is zero.
But we’ll need to play with the base case shortly, so let’s make it explicit:

{% highlight objc %}
// v2
- (NSUInteger)length {
    return [[self class] lengthOfListWithHead:self];
}

+ (NSUInteger)lengthOfListWithHead:(ListNode *)node {
    if (!node)
        return 0; // base case
    else
        return 1 + [self lengthOfListWithHead:node.next];
}
{% endhighlight %}

This code is **not** tail-recursive, and running it will create a stack frame for each list node.
This is undesirable because the list may have an arbitrary number of nodes[^node-limit], but the stack we’re using to count them has a relatively small fixed size, so with a sufficiently long list the stack *will* overflow and the program will crash.

[^node-limit]: As written here, where every node is an object in memory, of course there is a limit to those too. Both 32-bit and 64-bit address spaces allow *much* longer lists than the stack could could accommodate, though.

Let’s convert this to an iterative implementation:

{% highlight objc %}
// v3
- (NSUInteger)length {
    return [[self class] lengthOfListWithHead:self];
}

+ (NSUInteger)lengthOfListWithHead:(ListNode *)node {
    NSUInteger count = 0; // base case
    while (node) {
        count += 1;
        node = node.next;
    }
    return count;
}
{% endhighlight %}

Now calculating the length will use a constant number of stack frames[^frame-count], avoiding the problem above.
Some may argue that the elegance of the recursive approach has been lost, though.

[^frame-count]: Naively this will use 2 frames, one for `-[ListNode length]` and one for `+[ListNode lengthOfListWithHead:]`. If the tail call in `-[ListNode length]` can be turned into a jump, there may only be one frame; but it likely can’t be. See [Proper Tail Recursion in C](http://www.complang.tuwien.ac.at/schani/diplarb.ps).

Note that in each iteration, the code changes `node` — a parameter — as well a new local variable.
We can play with this, making a parameter for `count` as well:

{% highlight objc %}
// v4
- (NSUInteger)length {
    return [[self class] lengthOfListWithHead:self count:0 /* base case */];
}

+ (NSUInteger)lengthOfListWithHead:(ListNode *)node count:(NSUInteger)count {
    while (node) {
        count += 1;
        node = node.next;
    }
    return count;
}
{% endhighlight %}

Now unwrap the `while` loop:

{% highlight objc %}
// v5
+ (NSUInteger)lengthOfListWithHead:(ListNode *)node count:(NSUInteger)count {
top:
    if (!node) {
        return count;
    } else {
        count += 1;
        node = node.next;
        goto top;
    }
}
{% endhighlight %}

Pay attention to the code in `else` clause. This technique — setting parameters and jumping to the top of a method — is also known as **calling a method**:

{% highlight objc %}
// v6
+ (NSUInteger)lengthOfListWithHead:(ListNode *)node count:(NSUInteger)count {
    if (!node)
        return count;
    else
        return [self lengthOfListWithHead:node.next count:(count + 1)];
}
{% endhighlight %}

This is tail recursion.
The initial recursive implementation (v2) is **not** tail-recursive because each pass performs an addition after the recursive call returns.
The state of this incomplete addition must be stored somewhere, and that "somewhere" is the stack.

Let this soak in for a moment.

The compiler can see that these two forms are equivalent too.
With sufficient optimizations enabled — `-O1` for clang — the tail-recursive version is compiled into iterative code, using just one stack frame regardless of length.
This is called **[tail call optimization](http://en.wikipedia.org/wiki/Tail_call)** (TCO).

I happened across a discussion of [tail call optimization in ECMAScript / JavaScript](http://duartes.org/gustavo/blog/post/tail-calls-optimization-es6/) today, and decided to sanity check my understanding, so made a little Xcode project and wrote [the code above][gist].
I was surprised to see that v6 did **not** get its tail-call optimized:

<a href="/assets/2014-05-24-tail-recursion-objc-and-arc/v6-stack.png"><img alt="Key path warnings in Xcode" src="/assets/2014-05-24-tail-recursion-objc-and-arc/v6-stack.png" width="640"></a>

What is going on?
This *should* work; there is no work to be done after the recursive call, so why isn’t being optimized?
Dump the assembly! (Source annotations added by hand.)

{% highlight nasm %}
Tail`+[ListNode lengthOfListWithHead_v6:count:] at main.m:103:
0x100001ae0:  pushq  %rbp
0x100001ae1:  movq   %rsp, %rbp
0x100001ae4:  pushq  %r15
0x100001ae6:  pushq  %r14
0x100001ae8:  pushq  %r12
0x100001aea:  pushq  %rbx
0x100001aeb:  movq   %rcx, %rbx
0x100001aee:  movq   %rdi, %r14
    ; if (!node)
0x100001af1:  testq  %rdx, %rdx
0x100001af4:  je     0x100001b37               ; +[ListNode lengthOfListWithHead_v6:count:] + 87 at main.m:108
0x100001af6:  movq   0x8b3(%rip), %rsi         ; "next"
0x100001afd:  movq   0x514(%rip), %r12         ; (void *)0x00007fff99e68080: objc_msgSend
0x100001b04:  movq   %rdx, %rdi
    ;     node.next
0x100001b07:  callq  *%r12
0x100001b0a:  movq   %rax, %rdi
0x100001b0d:  callq  0x100001c9a               ; symbol stub for: objc_retainAutoreleasedReturnValue
0x100001b12:  movq   %rax, %r15
    ;     (count + 1)
0x100001b15:  incq   %rbx
0x100001b18:  movq   0x8c1(%rip), %rsi         ; "lengthOfListWithHead_v6:count:"
0x100001b1f:  movq   %r14, %rdi
0x100001b22:  movq   %r15, %rdx
0x100001b25:  movq   %rbx, %rcx
    ;     [self lengthOfListWithHead_v6:node.next count:(count + 1)];
0x100001b28:  callq  *%r12
0x100001b2b:  movq   %rax, %rbx
0x100001b2e:  movq   %r15, %rdi
0x100001b31:  callq  *0x4e9(%rip)              ; (void *)0x00007fff99e6b0d0: objc_release
0x100001b37:  movq   %rbx, %rax
0x100001b3a:  popq   %rbx
0x100001b3b:  popq   %r12
0x100001b3d:  popq   %r14
0x100001b3f:  popq   %r15
0x100001b41:  popq   %rbp
0x100001b42:  ret    
{% endhighlight %}

The problem is revealed: there **is** work to be done after the recursive call: automatic reference counting inserted a release call for the value returned from `node.next`.
If we were writing this with manual retain/release, one wouldn’t insert any memory management calls into this at all, because `-next` returns an autoreleased object.
However when this is compiled under ARC, calls to `objc_retainAutoreleasedReturnValue` and `objc_release` are inserted to allow for another optimization — having the return value skip the autorelease pool entirely.
Unfortunately in this case, it conflicts with tail call optimization.

One way to avoid this is to use the instance variable directly:

{% highlight objc %}
// v7
- (NSUInteger)length {
    return [[self class] lengthOfListWithHead:self count:0];
}
+ (NSUInteger)lengthOfListWithHead:(ListNode *)node count:(NSUInteger)count {
    if (!node)
        return count;
    else
        return [self lengthOfListWithHead:node->_next count:(count + 1)];
}
{% endhighlight %}

This generates much more compact assembly:

{% highlight nasm %}
Tail`+[ListNode lengthOfListWithHead_v7:count:] at main.m:115:
0x100001a50:  pushq  %rbp
0x100001a51:  movq   %rsp, %rbp
0x100001a54:  testq  %rdx, %rdx
0x100001a57:  je     0x100001a75               ; +[ListNode lengthOfListWithHead_v7:count:] + 37 at main.m:120
0x100001a59:  movq   0xaf0(%rip), %rax         ; ListNode._next
0x100001a60:  movq   (%rdx,%rax), %rdx
0x100001a64:  incq   %rcx
0x100001a67:  movq   0x9b2(%rip), %rsi         ; "lengthOfListWithHead_v7:count:"
0x100001a6e:  popq   %rbp
    ; The “jump” instead of “call” shows tail call optimization in effect
0x100001a6f:  jmpq   *0x5a3(%rip)              ; (void *)0x00007fff99e68080: objc_msgSend
0x100001a75:  movq   %rcx, %rax
0x100001a78:  popq   %rbp
0x100001a79:  ret    
{% endhighlight %}

However the behavior is slightly different: `node` could be an instance of a `ListNode` subclass that has overridden `next` to return something different. The compiler, being conservative, won’t replace the message send with an instance variable access for this reason.

So depending on the use case, we might choose to:

<ol><!-- Switch to HTML so code block can be in the li, sigh -->
<li>
Assume <code>next</code> isn’t overridden, access the ivar directly, and get tail call optimization.
</li>

<li>
Try to handle both situations:

{% highlight objc %}
// v8
+ (NSUInteger)lengthOfListWithHead:(ListNode *)node count:(NSUInteger)count {
    if (!node)
        return count;
    else if ([node isMemberOfClass:self])
        return [self lengthOfListWithHead:node->_next count:(count + 1)];
    else
        return [self lengthOfListWithHead:node.next count:(count + 1)];
}
{% endhighlight %}
  
<p>
Unfortunately I was unable to get this to work, even trying a variety of ways to check the class there would always be unconditional release calls inserted at the end of the method that thwarted TCO.
</p>
</li>

<li>
Compile this code without ARC, allowing TCO at the cost of autorelease optimization.

<p>
But the <strong>best</strong> choice is:
</p>
</li>

<li>
Admit defeat, and just use explicit iteration.
</li>
</ol>

In an ARC environment, tail call optimization (and thus tail recursion) is too fragile. Don’t rely on it.


[gist]: https://gist.github.com/jmah/bf846e6fc39cbc9d23c2

[^send-to-nil]: See [Programming with Objective-C: Working with nil](https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/WorkingwithObjects/WorkingwithObjects.html#//apple_ref/doc/uid/TP40011210-CH4-SW22)
