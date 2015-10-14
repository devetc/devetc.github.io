---
layout: post
title:  "No parameters"
date:   2015-10-14 15:48:47 -0700
categories: code
tags: cocoa blocks C
subtitle: Empty parentheses are not "no parameters" in (Objective-)C.
---


In a lot of Objective-C code (and also some C), I have come across the misconception that `()` means "no parameters". For example, I see code like:

{% highlight objc %}
void thisCFunctionTakesNoParameters() {
    puts("Hello, world!");
}

typedef void (^plainCallback_t)();
{% endhighlight %}

In fact just after block support was added, while still struggling with the syntax I discovered that the following compiled:

{% highlight objc %}
- (void)someMethod {
    NSString *(^iAmClever)() = ^(NSString *foo, NSString *bar) {
        return [foo stringByAppendingString:bar];
    };
    NSLog(@"joined: %@", iAmClever(@"John ", @"Doe"));
}
{% endhighlight %}

"Wow," I thought, "I can shorten my syntax because it must infer the parameter types!" So I used this merrily, but then stuff went wrong and I learned the truth.


# Reality

Using `()` in a function type declaration means **unspecified parameters**.
This is a very old feature of C that has been maintained for backward compatibility. In fact, it was noted as an "obsolescent feature" in C89 — yes, that's 1989![^fn-c89]

[^fn-c89]: From the [C89 standard](http://port70.net/~nsz/c/c89/c89-draft.txt): "3.9.4 Function declarators:
The use of function declarators with empty parentheses (not prototype-format parameter type declarators) is an obsolescent feature".


Arguments passed to a function (or block) declared with `()` will use "default argument promotions", which means they will not be the type declared by the block:

{% highlight objc %}
int main(int argc, const char *argv[]) {
    void (^block)() = ^(NSInteger arg) {
        NSLog(@"arg = %ld", arg);
    };

    block(42); // arg = 42

    block(-1); // arg = 4294967295
    block((NSInteger)-1); // arg = -1

    CGRect frame = CGRectMake(10, 10, 50, 50);
    block(frame.origin.x); // arg = 4294984304

    block(@"fifteen"); // arg = 4294984432

    block(); // arg = 4294984304

    block("somewhere", "over", "the", "rainbow"); // arg = 4294981825

    return 0;
}
{% endhighlight %}

The above compiles with no warnings whatsoever, even with `-Weverything`.
The warning that *should* catch this is `-Wstrict-prototypes`, but this doesn't seem functional in clang (it's [documented for GCC](https://gcc.gnu.org/onlinedocs/gcc-4.9.2/gcc/Warning-Options.html#index-Wstrict-prototypes-491)).

Because this warning is apparently unimplemented, huge amounts of otherwise high quality code has these turds lurking in both public API and implementation:

- [ReactiveCocoa][rac] (e.g. `-[RACStream reduceEach:(id (^)())reduceBlock]`)
- [Mixpanel][mixpanel] (e.g. `-[Mixpanel flushWithCompletion:(void (^)())handler]`)
- [Facebook FBSDKCoreKit][fbsdkcorekit] (implementation only)
- [AFNetworking][afnetworking] (implementation only)

Even UIKit made this mistake!

{% highlight objc %}
- (void)application:(UIApplication *)application
  handleEventsForBackgroundURLSession:(NSString *)identifier
  completionHandler:(void (^)())completionHandler
{% endhighlight %}

The `completionHandler` block has since been marked `(void)` in the current [online documentation][adc-docs], but the headers in the iOS 9.0 SDK still show it as `()`.

[rac]: https://github.com/ReactiveCocoa/ReactiveCocoa/blob/e16f47cf9cb568136ebd81430b24af274c3c27c7/ReactiveCocoa/Objective-C/RACStream.h#L171
[mixpanel]: https://github.com/mixpanel/mixpanel-iphone/blob/bdd0f5a7f33ea0bfc4193f84ae2ed80258215bab/Mixpanel/Mixpanel.h#L559
[fbsdkcorekit]: https://github.com/facebook/facebook-ios-sdk/blob/61b636f61d67337d59741177289cdfe5ec0e5667/FBSDKCoreKit/FBSDKCoreKit/FBSDKGraphRequestConnection.m#L709
[afnetworking]: https://github.com/AFNetworking/AFNetworking/blob/fbd2bc8ac9353e6b9d2871b2a6a5cbc75b5ba841/AFNetworking/AFHTTPRequestOperation.m
[adc-docs]: https://developer.apple.com/library/ios/documentation/UIKit/Reference/UIApplicationDelegate_Protocol/#//apple_ref/occ/intfm/UIApplicationDelegate/application:handleEventsForBackgroundURLSession:completionHandler:



# Let's fix this!

I have filed Radar 23116994 (view [23116994 on Open Radar][oradar]). [LLVM bug 20796][llvmbug] has been open since August 2014 but hadn’t moved. I’ve just commented on it, and have begun submitting pull requests to projects when I come across it (e.g. [facebook-ios-sdk][fb-block-pr]).

You can start by searching your own code for `)()` and `() {` — not all results will be cases, and not all cases will be found by this but it’s a starting point.

[oradar]: http://www.openradar.me/23116994
[llvmbug]: https://llvm.org/bugs/show_bug.cgi?id=20796
[fb-block-pr]: https://github.com/facebook/facebook-ios-sdk/pull/795
