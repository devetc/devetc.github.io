---
layout: post
title: "Safe and Sane Key Paths"
date: 
categories: code
tags: git
subtitle: Dealing with those static strings.
---

[Key–value coding][kvc] — `valueForKeyPath:` and `setValue:forKeyPath:` — is very useful for converting data from one format to another, such as copying from a property list-like structure (e.g. deserialized JSON) into model objects proper.
This avoids a lot of boilerplate typically found in, for example, Java-based systems[^java-boilerplate].

On the Mac, with [Cocoa Bindings][bindings] you can throw together a simple UI in a flash, setting up key paths in Interface Builder.
On iOS you have to provide some of the glue yourself, but you typically let [key–value observing][kvo] do the hardest work.


## The problem

These "key–value" techniques have one main thing in common:
They use strings to reference code.
This makes it fragile. For example:

{% highlight objc %}
@implementation ContrivedExample
- (NSString *)title
{ return @"foo"; }

- (NSUInteger)contrivedLength
{ return [[self title] length]; }

- (NSUInteger)contrivedLengthKVC
{ return [[self valueForKey:@"title"] length]; }
@end
{% endhighlight %}

If we rename the method `title`, the compiler will immediately show that `contrivedLength` won't work without changes.
But `contrivedLengthKVC` will have no such warning, because `@"title"` remains a perfectly valid string.
We would only see an error at run-time, if and when that code was triggered.
Of course in real code, string references like this appear much further apart than in the above snippet, making stale references and even typos a real problem.


## The common solution

In short:
**The compiler does not validate key paths, because they are strings.**

One approach toward validation is avoid strings[^stringly-typed]. Of course, a string must emerge at some point, but pre-processor macros allow using the same expression (`title`) as both code and data, at compile-time.
Many have taken this route, resulting in a large variety[^safe-kvc-links] with different trade-offs. A couple that are representative:

1. With [libextobjc][libextobjc-kvc] you have to specify the target of the key path twice — `[self valueForKey:@keypath(self.title)]` above — though this is often redundant, and obscures that the resulting string will be simply "title".
2. [DMSafeKVC][dmsafekvc] is more concise at use — `[self valueForKey:K(title)]` — but require annotating declarations, and only checks that *some* class has an annotated “title” accessor.

[^safe-kvc-links]: [Uli Kusterer's approach using `@selector`](http://orangejuiceliberationfront.com/safe-key-value-coding/);<br>[Nicolas Bouilleaud's approach using `@selector`](https://gist.github.com/n-b/2394297);<br>[Kyle Van Essen's approach using declared targets](https://gist.github.com/kyleve/8213806);<br>[Andrew Pouliot's approach using declared targets](https://gist.github.com/darknoon/4482025);<br>[Martin Kiss's approach using declared targets](https://github.com/iMartinKiss/Valid-KeyPath);<br>and many more.

Compiler error messages are typically obscured due to macro expansion. And if you're writing library code[^library-code], often the best approach is to use the lowest common denominator — static strings.

[^library-code]: "Library code" refers to code shared between projects which might use different safe KVC techniques, or none at all.

A few months back, my colleagues at Fitbit discussed the ups and downs of various macro implementations and didn't arrive at consensus.
Additionally, retrofitting our codebase would be a mostly manual task and likely generate many conflicts (our repository has around 10 active committers).

I began to consider a different approach.


## The code less traveled

**The compiler does not validate key paths, because they are strings.**
In our phrasing of the problem, a second solution becomes apparent: make the compiler validate the strings!

<a href="/assets/2014-05-17-safe-and-sane-key-paths/warnings.png"><img alt="Key path warnings in Xcode" src="/assets/2014-05-17-safe-and-sane-key-paths/warnings.png" width="640"></a>

In the past, touching the compiler has been considered off-the-table for various reasons. With clang, this is now more practical[^practicality], but the previous stigma still lingers.

This code is currently proof-of-concept quality.
(I'm only a C++ novice, and barely familiar with the clang codebase.)
It currently:

- Checks some hard-coded method calls that are passed string literal arguments (including macros that expand to string literals).
- Validates that there are corresponding getter methods, recursing down the key path.
- Checks for a method named `key` or `isKey`, or a collection property that might be backed with [KVC collection accessor methods][kvc-collection].
- Does no checking if the type is `id`, `NSDictionary`, a class annotated with `objc_kvc_container`, or a few more.
- Knows that scalar numbers will be returned as `NSNumber`.
- Uses the diagnostic output of the secondary clang, but the binary output of Xcode's bundled clang.

The compiler plug-in doesn't do everything that some of the macro approaches do, but has the giant advantage of requiring zero code changes and no dependencies.
It also doesn't exclude the use of macros, either.
Only one small project setting change is required:

<img alt="Key path warnings in Xcode" src="/assets/2014-05-17-safe-and-sane-key-paths/build-setting.png" width="642">

If you'd like to try this with your own project, look at the [Clang-KeyPathValidator](https://github.com/jmah/Clang-KeyPathValidator) README file.
Then check out the [GitHub Issues](https://github.com/jmah/Clang-KeyPathValidator/issues) page and see if you can help out with something.
Or just help get the word out!



[^java-boilerplate]: This opinion is several years old, before Java reflection was commonly available or efficient.
[^stringly-typed]: The term "stringly-typed" is just great.
[^practicality]: It's unfortunately still not completely painless, because the particular versions shipped by Apple with Xcode are not made publicly available, and have plug-in support disabled.

[kvc]: https://developer.apple.com/library/mac/documentation/cocoa/Conceptual/KeyValueCoding/Articles/KeyValueCoding.html
[bindings]: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/CocoaBindings/CocoaBindings.html
[kvo]: https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/KeyValueObserving/KeyValueObserving.html
[libextobjc-kvc]: https://github.com/jspahrsummers/libextobjc/blob/master/extobjc/EXTKeyPathCoding.h
[dmsafekvc]: https://github.com/delicious-monster/DMSafeKVC
[kvc-collection]: https://developer.apple.com/library/ios/documentation/cocoa/conceptual/KeyValueCoding/Articles/AccessorConventions.html#//apple_ref/doc/uid/20002174-178830-BAJEDEFB
